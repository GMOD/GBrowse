package Bio::Graphics::Glyph::insertion_chromosome;

use strict;
#use Bio::Graphics::Glyph::generic;
use vars '@ISA';
@ISA = 'Bio::Graphics::Glyph::generic';

use GD 'gdTinyFont';

# override draw_component to draw a chromosome
sub draw_component {
  my $self = shift;
  my $gd = shift;
  my ($left,$top) = @_;
  my($x1,$y1,$x2,$y2) = $self->bounds(@_); 

  require GD;
  my $poly = GD::Polygon->new;
  my $white = $gd->colorAllocate(255,255,255);
  my $black = $gd->colorAllocate(0,0,0);
  my $red   = $gd->colorAllocate(255,0,0);
  my $pink  = $gd->colorAllocate(255,100,220);
  my $blue  = $gd->colorAllocate(0,0,255);
  my $purple= $gd->colorAllocate(120,80,255);
  my $yellow= $gd->colorAllocate(225,225,0);
  my $green = $gd->colorAllocate(0,225,0);

  my $Ty = 2*$y2/3;
  my $By = $y2;
  my $left = -10+$self->panel->left;
  my $right= $self->panel->right;
  my $length = 10+$right-$left;
  my $top_arm = $x1;
  $poly->addPt($left+10, $Ty);
  $poly->addPt($left+2, $Ty+3);
  $poly->addPt($left, $Ty+6);
  $poly->addPt($left, $By-6);
  $poly->addPt($left+2, $By-3);
  $poly->addPt($left+10, $By);
  $poly->addPt($left+$top_arm-4, $By);
  $poly->addPt($left+$top_arm-1, $By-2);
  $poly->addPt($left+$top_arm, $By-5);
  $poly->addPt($left+$top_arm+1, $By-2);
  $poly->addPt($left+$top_arm+4, $By);
  $poly->addPt($left+$length-10, $By);
  $poly->addPt($left+$length-2, $By-3);
  $poly->addPt($left+$length, $By-6);
  $poly->addPt($left+$length, $Ty+6);
  $poly->addPt($left+$length-2, $Ty+3);
  $poly->addPt($left+$length-10, $Ty);
  $poly->addPt($left+$top_arm+4, $Ty);
  $poly->addPt($left+$top_arm+1, $Ty+2);
  $poly->addPt($left+$top_arm, $Ty+5);
  $poly->addPt($left+$top_arm-1, $Ty+2);
  $poly->addPt($left+$top_arm-4, $Ty);

  #$gd->filledPolygon($poly, $self->fillcolor);
  $gd->polygon($poly, $self->fgcolor);

  #my $agg = Bio::DB::GFF::Aggregator->new(-method    => 'insertion',
  #                                        -sub_parts => 'seq:experiment');

  #my $database = $self->option('database');
  #my $user     = $self->option('user');
  #my $password = $self->option('password');
  #my $db  = Bio::DB::GFF->new( -dsn=>$database,
  #                             -user=>$user,
  #                             -pass=>$password,
  #                             -aggregators=>$agg);
  
  my $seq_id = $self->feature->seq_id;
  my $dbh = $self->feature->factory->features_db;
  my $qry1 = "select fstart, fstop 
              from fdata, fgroup  
              where fref = '$seq_id' 
                    and fdata.gid = fgroup.gid
                    and fgroup.gclass = 'Sequence'";
  my $qry2 = "select gname, fstart  
              from fdata, fgroup
              where fdata.gid = fgroup.gid 
                    and fdata.fref = '$seq_id' 
                    and fgroup.gclass='Seq'"; 
  my $sth1 = $dbh->prepare($qry1);
  $sth1->execute();
  my ($chr_start, $chr_stop); 
  $sth1->bind_columns( undef, \$chr_start, \$chr_stop);
  my $chr_len = $chr_stop - $chr_start if $sth1->fetch();  
  $sth1->finish();

  #my $segment  = $db->segment($self->feature->seq_id);
  #my $chr_len  = $segment->abs_stop - $segment->abs_start;
  #my @features = $segment->features('insertion');

  my $sth2 = $dbh->prepare($qry2);
  my ($name, $start);
  $sth2->execute();
  $sth2->bind_columns( undef, \$name, \$start);
  while ($sth2->fetch()) {
   
      my $line_color;
      if ($name =~ /dspm/) {
	 $line_color = $blue;                 
      } elsif ($name =~ /SM/) {
	$line_color = $purple;
      } elsif ($name =~ /AT/) {
	$line_color = $green;
      } elsif ($name =~ /GT/) {
	$line_color = $red;
      } elsif ($name =~ /ET/) {
	$line_color = $pink;
      } else {
	$line_color = $yellow;
      }

      my $pos = int($start*($length-20)/$chr_len);
      my ($y1, $y2); 
      my $top_arm = $top_arm-10;
      if (($pos > $top_arm-4 && $pos <= $top_arm-3) || 
	  ($pos >= $top_arm+3 && $pos < $top_arm+4)) { 
          $y1 = $Ty+2;
          $y2 = $By-2;

      } elsif (($pos > $top_arm-3 && $pos <= $top_arm-2) ||
	       ($pos >= $top_arm+2 && $pos < $top_arm+3)) { 
          $y1 = $Ty+4;
          $y2 = $By-4;

      } elsif (($pos > $top_arm-2 && $pos <= $top_arm-1) ||
	       ($pos >= $top_arm+1 && $pos < $top_arm+2)) { 
          $y1 = $Ty+5;
          $y2 = $By-5;

      } elsif ($pos == $top_arm) {
          $y1 = $Ty+7;
          $y2 = $By-7;

      } else {
          $y1 = $Ty+1;
          $y2 = $By-1;
      }
      $gd->line($left+$pos+10, $y1, $left+$pos+10, $y2, $line_color);      
  } 
  $sth2->finish();
  $dbh->disconnect();
  #$gd->string(gdTinyFont, $left, $y1, $temp, $red);
   
}



# group sets connector to 'solid'
sub connector {
  my $self = shift;
  return $self->SUPER::connector(@_) if $self->all_callbacks;
  return 'solid';
}

sub bump {
  my $self = shift;
  return $self->SUPER::bump(@_) if $self->all_callbacks;
  return 0;
}


1;


=head1 NAME

Bio::Graphics::Glyph::insertion_chromosome - The "insertion_chromosome" glyph

=head1 SYNOPSIS

  See L<Bio::Graphics::Panel> and L<Bio::Graphics::Glyph>.

=head1 DESCRIPTION

This glyph was designed to show seq features in round edge rectangles.
The glyph will be a rectangle if its width is E<lt> 4 pixels

=head1 BUGS

Please report them.

=head1 SEE ALSO


L<Bio::Graphics::Panel>,
L<Bio::Graphics::Glyph>,
L<Bio::Graphics::Glyph::arrow>,
L<Bio::Graphics::Glyph::cds>,
L<Bio::Graphics::Glyph::crossbox>,
L<Bio::Graphics::Glyph::diamond>,
L<Bio::Graphics::Glyph::dna>,
L<Bio::Graphics::Glyph::dot>,
L<Bio::Graphics::Glyph::ellipse>,
L<Bio::Graphics::Glyph::extending_arrow>,
L<Bio::Graphics::Glyph::generic>,
L<Bio::Graphics::Glyph::graded_segments>,
L<Bio::Graphics::Glyph::heterogeneous_segments>,
L<Bio::Graphics::Glyph::line>,
L<Bio::Graphics::Glyph::pinsertion>,
L<Bio::Graphics::Glyph::primers>,
L<Bio::Graphics::Glyph::rndrect>,
L<Bio::Graphics::Glyph::chromosome>,
L<Bio::Graphics::Glyph::segments>,
L<Bio::Graphics::Glyph::ruler_arrow>,
L<Bio::Graphics::Glyph::toomany>,
L<Bio::Graphics::Glyph::transcript>,
L<Bio::Graphics::Glyph::transcript2>,
L<Bio::Graphics::Glyph::translation>,
L<Bio::Graphics::Glyph::triangle>,
L<Bio::DB::GFF>,
L<Bio::SeqI>,
L<Bio::SeqFeatureI>,
L<Bio::Das>,
L<GD>

=head1 AUTHOR

Xiaokang Pan E<lt>pan@cshl.orgE<gt>

Copyright (c) 2001 BDGP

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut
