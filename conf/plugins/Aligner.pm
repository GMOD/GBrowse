package Bio::Graphics::Browser::Plugin::Aligner;
# $Id: Aligner.pm,v 1.1 2003-05-21 13:45:12 lstein Exp $
use strict;
use Bio::Graphics::Browser::Plugin;
use CGI qw(table TR td th p popup_menu radio_group checkbox checkbox_group h1 h2 pre);
use Text::Shellwords;
use Bio::Graphics::Browser::Realign 'align_segs';
use Bio::Graphics::Browser::PadAlignment;

use constant DEBUG => 0;
use constant DEFAULT_RAGGED_ENDS => (0,10,25,50,100,150,500);

use vars '$VERSION','@ISA';
$VERSION = '0.10';
@ISA = qw(Bio::Graphics::Browser::Plugin);

use constant TARGET    => 0;
use constant SRC_START => 1;
use constant SRC_END   => 2;
use constant TGT_START => 3;
use constant TGT_END   => 4;

sub name { "Alignments" }

sub description {
  p("This plugin prints out a multiple alignment of the selected features.",
    'It was written by',a({-href=>'mailto:lstein@cshl.org'},'Lincoln Stein.')
   );
}

sub init {
  my $self = shift;
  my $browser_conf = $self->browser_config;
  my @alignable       = shellwords($browser_conf->plugin_setting('alignable_tracks'));
  @alignable = grep {$browser_conf->setting($_=>'draw_target') } $browser_conf->labels
    unless @alignable;
  $self->{alignable} = \@alignable;

  my @upcase          = shellwords($browser_conf->plugin_setting('upcase_tracks'));
  $self->{upcase}     = \@upcase;

  my @ragged          = shellwords($browser_conf->plugin_setting('ragged_ends'));
  @ragged             = DEFAULT_RAGGED_ENDS unless @ragged;
  $self->{ragged}     = \@ragged;

  $self->{upcase_default} = $browser_conf->plugin_setting('upcase_default');
  $self->{ragged_default} = $browser_conf->plugin_setting('ragged_default');

}

sub config_defaults {
  my $self = shift;
  return { align  => $self->{alignable},
	   upcase => $self->{upcase},
	   flip   => 0,
	 };
}

sub configure_form {
  my $self    = shift;
  my $current = $self->configuration;
  my $browser = $self->browser_config;
  my $html;
  if ($self->{upcase}) {
    my %labels = map {$_ => $browser->setting($_=>'key') || $_} @{$self->{upcase}};
    $html .= TR(
		th('Features to render uppercase:'),
		td(radio_group(-name    => $self->config_name('upcase'),
			       -values  => ['none',@{$self->{upcase}}],
			       -default => $current->{upcase} || $self->{upcase_default} || 'none',
			       -labels   => \%labels,
			       @{$self->{upcase}} > 4 ? (-cols     => 4) : ()
			      ))
	       );
  }
  if ($self->{alignable} && @{$self->{alignable}}) {
    my %labels = map {$_ => $browser->setting($_=>'key') || $_} @{$self->{alignable}};
    $html .= TR(
		th('Features to include in alignment:'),
		td(checkbox_group(-name     => $self->config_name('align'),
				  -values   => $self->{alignable},
				  -defaults => $current->{align},
				  -labels   => \%labels,
				  @{$self->{alignable}} > 4 ? (-cols     => 4) : ()
				 )));
  }
  $html .= TR(
	      th({-colspan=>2,-align=>'left'},
		 'Allow up to',popup_menu(-name     => $self->config_name('ragged'),
					  -values   => $self->{ragged},
					  -default  => $current->{ragged} || $self->{ragged_default} || 0),
		 '&nbsp;bp of unaligned sequence at ends.')
	      );
  $html .= TR(
	      th({-colspan=>2,-align=>'left'},
		 checkbox(-name     => $self->config_name('flip'),
			  -default  => $current->{flip},
			 -label     => 'Reverse complement alignment')));
  return $html ? table({-class=>'searchtitle'},$html) : undef;
}

sub reconfigure {
  my $self = shift;
  my $current = $self->configuration;
  my @align   = $self->config_param('align');
  my $upcase  = $self->config_param('upcase');
  $current->{align}  = \@align;
  $current->{upcase} = $upcase eq 'none' ? undef : $upcase;
  $current->{ragged} = $self->config_param('ragged');
  $current->{flip}   = $self->config_param('flip');
}

sub mime_type { 'text/html' }

sub dump {
  my $self    = shift;
  my $segment = shift;

  my $database      = $self->database;
  my $browser       = $self->browser_config;
  my $configuration = $self->configuration;

  my $flipped = $configuration->{flip} ? " (reverse complemented)" :'';
  print h1("Alignments for $segment$flipped");

  my $ref_dna = lc $segment->seq;
  my ($abs_start,$abs_end) = ($segment->start,$segment->end);


  # do upcasing
  if (my $upcase_track  = $configuration->{upcase}) {
    my @upcase_types    = shellwords($browser->setting($upcase_track=>'feature'));
    my @upcase_features = $segment->features(-types=>\@upcase_types);
    for my $f (@upcase_features) {
      my @segments = $f->segments;
      @segments    = $f unless @segments;
      for my $s (@segments) {
	substr($ref_dna,$s->low-$abs_start,$s->length) =~ tr/a-z/A-Z/;
      }
    }
  }

  # here's where we handle aligned objects
  my @feature_types = map {shellwords($browser->setting($_=>'feature'))} @{$configuration->{align}};
  my @features      = $segment->features(-types=>\@feature_types);

  my (@segments,%strands);

  for my $f (@features) {
    my @s = $f->segments;
    @s    = $f unless @s;

    for my $s (@s) {
      my $target = $s->target;
      my ($src_start,$src_end) = ($s->start,$s->end);
      my ($tgt_start,$tgt_end) = ($target->start,$target->end);

      unless (exists $strands{$target}) {
	my $strand = $f->strand;
	$strand    = -1 if $tgt_start > $tgt_end;  # fix data bugs in some GFF files
	$strands{$target} = $strand;
      }
      ($tgt_start,$tgt_end) = ($tgt_end,$tgt_start) if $strands{$target} < 0;

      # If the source and target length match, then we are home free
      if ($s->length == $target->length) {
	push @segments,[$target,$src_start,$src_end,$tgt_start,$tgt_end];
      }

      else {  # unfortunately if this isn't the case, then we have to realign the segment a bit
	warn "Realigning. Probably won't work!" if DEBUG;
	push @segments,map {
	  [$target,$_->[0]+$src_start,$_->[1]+$src_start,$_->[2]+$tgt_start,$_->[3]+$tgt_start]
	}
	  $self->realign($segment->dna,$target->dna);
      }
    }
  }

  # We're now going to  all the alignments
  my %clip;
  for my $seg (@segments) {
    my $target = $seg->[TARGET];

    # left clipping
    if ( (my $delta = $seg->[SRC_START] - $abs_start) < 0 ) {
      warn "clip left $delta" if DEBUG;
      $seg->[SRC_START] = $abs_start;
      if ($strands{$target} >= 0) {
	$seg->[TGT_START] -= $delta;
      } else {
	$seg->[TGT_END]  +=  $delta;
      }
    }

    # right clipping
    if ( (my $delta = $abs_end - $seg->[SRC_END]) < 0) {
      warn "clip right $delta" if DEBUG;
      $seg->[SRC_END] = $abs_end;
      if ($strands{$target} >= 0) {
	$seg->[TGT_END]   += $delta;
      } else {
	$seg->[TGT_START] -= $delta;
      }
    }

    $clip{$target}{low} = $seg->[TGT_START]
      if !defined $clip{$target}{low} || $clip{$target}{low} > $seg->[TGT_START];
    $clip{$target}{high} = $seg->[TGT_END]
      if !defined $clip{$target}{high} || $seg->[TGT_END] > $clip{$target}{high};
  }

  my $ragged = $configuration->{ragged} || 0;

  # sort aligned sequences from left to right and store them in the data structure
  # needed by Bio::Graphics::Browser::PadAlignment
  my @sequences = ($segment->display_name => $ref_dna);

  my %seqs;
  for my $t (sort {$clip{$a}{low}<=>$clip{$b}{low}} keys %clip) {

    # adjust for ragged ends
    $clip{$t}{low}  -= $ragged;
    $clip{$t}{high} += $ragged;

    $clip{$t}{low}   = 1 if $clip{$t}{low} < 1;

    my @order = $strands{$t}>=0?('low','high'):('high','low');
    my $dna = $database->dna($t,@{$clip{$t}}{@order});
    push @sequences,($t => $dna);  # dna() api gives implicit reversec

    # sanity check - needed for adjusting for ragged ends
    warn "$t low = $clip{$t}{low}, dna = $dna\n" if DEBUG;
    warn "expected ",$clip{$t}{high}-$clip{$t}{low}+1," but got ",length($dna) if DEBUG;
    $clip{$t}{high} = $clip{$t}{low}+length($dna)-1 if $clip{$t}{high} > $clip{$t}{low}+length($dna)-1;
  }

  for my $seg (@segments) {
    my ($target,$src_start,$src_end,$tgt_start,$tgt_end) = @$seg;
    warn "was [$target,$src_start,$src_end,$tgt_start,$tgt_end]" if DEBUG;
    $seg->[SRC_START] -= $abs_start;
    $seg->[SRC_END]   -= $abs_start;
    if ($strands{$target} >= 0) {
      $seg->[TGT_START] -= $clip{$target}{low};
      $seg->[TGT_END]   -= $clip{$target}{low};
    } else {
      @{$seg}[TGT_START,TGT_END] = ($clip{$target}{high} - $seg->[TGT_END],
				    $clip{$target}{high} - $seg->[TGT_START]);
    }
    ($target,$src_start,$src_end,$tgt_start,$tgt_end) = @$seg;
    warn "is  [$target,$src_start,$src_end,$tgt_start,$tgt_end]" if DEBUG;
  }

  my $align = Bio::Graphics::Browser::PadAlignment->new(\@sequences,\@segments);
  my %offsets = map {$_ => $strands{$_} >= 0 ? $clip{$_}{low} : -$clip{$_}{low}} keys %clip;
  $offsets{$segment->display_name} = $abs_start;

  print pre($align->alignment(\%offsets,{show_mismatches => 1,
					 flip            => $configuration->{flip}}
			     ));
}

sub realign {
  my $self = shift;
  my ($src,$tgt) = @_;
  return align_segs($src,$tgt);
}

sub reversec {
  my $dna = reverse shift;
  $dna =~ tr/gatcGATC/ctagCTAG/;
  $dna;
}

1;

