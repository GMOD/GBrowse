#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include "realign.h"

#define DBG 0

static ACellPtr new_row (int len) {
  return (ACellPtr) calloc(len,sizeof(ACell));
}

static void initMatrix(MatchMatrix* matrix) {
  matrix->match      = 1;
  matrix->mismatch   = -1;
  matrix->gap        = -2;
  matrix->gap_extend = 0;
  matrix->wcmatch    = 0;
  matrix->wildcard   = 'N';
}

/* note if matrix is NULL then use a standard matrix */
int realign (const char* src, const char* tgt, 
	     const MatchMatrixPtr matrix,
	     AlignmentPtr *align_out) {
  int                 src_len,tgt_len;
  int                 row,col,score;
  char                src_chr,tgt_chr;
  int                 extend_score,gap_src_score,gap_tgt_score,i;
  MatchMatrix         defmat,*mat;
  ACellPtr            *dpm;
  AlignmentPtr        alignment;
  bestcelldata        best_cell;  

  /* initialize matrix */
  if (matrix == NULL) {
    initMatrix(&defmat);
    mat = &defmat;
  } else {
    mat = matrix;
  }

  src_len = strlen(src);
  tgt_len = strlen(tgt);

  dpm    = (ACellPtr*) calloc(src_len+1,sizeof(ACellPtr));
  dpm[0] = new_row(tgt_len+1);

  best_cell.row   = 0;
  best_cell.col   = 0;
  best_cell.score = -999999;

#if DBG
  fprintf(stderr,"%-4c %-4c",' ',' ');
  for (i=0;i<tgt_len;i++)
    fprintf(stderr," %5c",tgt[i]);
  fprintf(stderr,"\n");
  fprintf(stderr,"%-4c ",' ');
  for (i=0; i<=tgt_len; i++) {
    fprintf(stderr,"%4d  ",dpm[0][i].score);
  }
  fprintf(stderr,"\n");
#endif

  for (row=0; row<src_len; row++) {

    src_chr  = toupper(src[row]);

#if DBG
    fprintf(stderr,"%-4c ",src_chr);
#endif

    /* current position is [row+1][col+1] */
    dpm[row+1] = new_row(tgt_len+1);

    for (col=0; col<tgt_len; col++) {

      tgt_chr = toupper(tgt[col]);

      extend_score =  dpm[row][col].score +
	(
	 (tgt_chr == mat->wildcard  || src_chr == mat->wildcard)  ? mat->wcmatch
	 : (tgt_chr == src_chr) ? mat->match
	                        : mat->mismatch
	 );

      /* what happens if we extend the src one character, gapping tgt? */
      gap_tgt_score = dpm[row+1][col].score + 
	((dpm[row+1][col].event == GAP_TGT) ? mat->gap_extend : mat->gap);

      /* what happens if we extend the tgt strand one character, gapping src? */
      gap_src_score = dpm[row][col+1].score + 
	((dpm[row][col+1].event == GAP_SRC) ? mat->gap_extend : mat->gap);

      /* find best score among the possibilities */
      if (gap_src_score >= gap_tgt_score && gap_src_score >= extend_score) {
	score = dpm[row+1][col+1].score = gap_src_score;
	dpm[row+1][col+1].event = GAP_SRC;
      }
      else if (gap_tgt_score >= extend_score) {
	score = dpm[row+1][col+1].score = gap_tgt_score;
	dpm[row+1][col+1].event = GAP_TGT;
      } else {
	score = dpm[row+1][col+1].score = extend_score;
	dpm[row+1][col+1].event = A_EXTEND;
      }
     
      /* save it for posterity */
      if (score >= best_cell.score) {
	best_cell.score = score;
	best_cell.row   = row+1;
	best_cell.col   = col+1;
      }
    }
#if DBG
    for (i=0; i<=tgt_len; i++) {
      fprintf(stderr,"%4d%1s ",dpm[row+1][i].score,
	                       ( dpm[row+1][i].event==A_EXTEND ? "e"
				 :dpm[row+1][i].event==GAP_SRC  ? "s"
	                         :"t"));
    }
    fprintf(stderr,"\n");
#endif
  }

  /* now do the trace back */
#if DBG
  fprintf(stderr,"starting traceback\n");
#endif
  row = best_cell.row;
  col = best_cell.col;
  alignment = (AlignmentPtr) calloc(src_len,sizeof(int));

  for (i=0;i<src_len;i++)
    alignment[i] = -1;

  while (row > 0 && col > 0) {
#if DBG
    fprintf(stderr,"row=%d, col=%d, score=%d, event=%s\n",row,col,dpm[row][col].score,
	    dpm[row][col].event==A_EXTEND ? "extend"
           :dpm[row][col].event==GAP_TGT  ? "gap_tgt"
           :dpm[row][col].event==GAP_SRC  ? "gap_src"
	   :"error");
#endif

    alignment[row-1] = col-1;
    if (dpm[row][col].event == A_EXTEND) {
      row--; col--;
    }

    else if (dpm[row][col].event == GAP_TGT) {
      col--;
    }

    else {
      alignment[row-1] = -1;  /* -1 means no match */
      row--;
    }
  }

#if DBG
  fprintf(stderr,"traceback done\n");
#endif

  *align_out = alignment;

#if DBG
  for (i=0;i<src_len;i++) {
    fprintf(stderr,"%3d %1c %3d %1c\n",
	    i,src[i],alignment[i],alignment[i]>=0 ? tgt[alignment[i]] : '-');
  }
#endif


  /* clean up */
  for (row=0; row<=src_len; row++) {
    free(dpm[row]);
  }
  free(dpm);
  return best_cell.score;
}

MODULE = Bio::Graphics::Browser2::CAlign		PACKAGE = Bio::Graphics::Browser2::CAlign

void
_do_alignment(packname="Bio::Graphics::Browser2::CAlign",src,tgt,options=NULL)
     char*         packname
     char*         src
     char*         tgt
     SV*           options
     PROTOTYPE: $$;$
     PREINIT:
     MatchMatrix   matrix;
     HV*           optionh;
     SV            **value;
     int           score,i;
     AlignmentPtr  alignment;
     AV*           palign;
     PPCODE:
     {
       /* copy defaults from standardMatrix */
       initMatrix(&matrix);

       if (options != NULL) {
	 if (!SvROK(options) || (SvTYPE(SvRV(options)) != SVt_PVHV))
	   croak("_do_alignment(): third argument must be a hashref");
	 optionh = (HV*) SvRV(options);
	 if (value = hv_fetch(optionh,"match",strlen("match"),0))
	   matrix.match = SvIV(*value);
	 if (value = hv_fetch(optionh,"mismatch",strlen("mismatch"),0))
	   matrix.mismatch = SvIV(*value);
	 if (value = hv_fetch(optionh,"gap",strlen("gap"),0))
	   matrix.gap = SvIV(*value);
	 if (value = hv_fetch(optionh,"gap_extend",strlen("gap_extend"),0))
	   matrix.gap_extend = SvIV(*value);
	 if (value = hv_fetch(optionh,"wildcard_match",strlen("wildcard_match"),0))
	   matrix.wcmatch = SvIV(*value);
	 if (value = hv_fetch(optionh,"wildcard",strlen("wildcard"),0))
	   matrix.wildcard   = *SvPV_nolen(*value);
       }

       score = realign(src,tgt,&matrix,&alignment);

       palign = (AV*)sv_2mortal((SV*) newAV());
       av_extend(palign,strlen(src));
       for (i=0;i<strlen(src);i++)
	 if (alignment[i] >= 0)
	   av_push(palign,newSVnv(alignment[i]));
	 else
	   av_push(palign,&PL_sv_undef);

       XPUSHs(sv_2mortal(newSViv(score)));
       XPUSHs(sv_2mortal(newRV((SV*) palign)));
     }
