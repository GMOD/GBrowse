/* $Id: realign.h,v 1.1 2003-05-19 17:25:47 lstein Exp $ */
/* Fast implementation of a global dp aligner, used by the Realign.pm module
   for realigning short HSPs */

#ifndef REALIGN_H
#define REALIGN_H

#define A_EXTEND 0
#define GAP_SRC  1
#define GAP_TGT  2

typedef struct {
  int   score;
  short event;
} ACell,*ACellPtr;

typedef struct {
  short  match;
  short  mismatch;
  short  wcmatch;
  short  gap;
  short  gap_extend;
  char   wildcard;
} MatchMatrix, *MatchMatrixPtr;

typedef int *AlignmentPtr;

typedef struct {
  int score;
  int row;
  int col;
} bestcelldata;

int realign (const char* src, const char* tgt, 
	     const MatchMatrixPtr matrix,
	     AlignmentPtr *align_out);

#endif
