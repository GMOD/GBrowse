package Bio::Graphics::Browser2::DataLoader::bed;

# $Id$

use strict;
use Bio::DB::SeqFeature::Store;
use Carp 'croak';
use File::Basename 'basename';
use base 'Bio::Graphics::Browser2::DataLoader::generic';

use constant TOO_SMALL_FOR_SUMMARY_MODE => 10000;  # don't go into summary mode
my @COLORS = qw(blue red orange brown mauve peach 
                green cyan black yellow cyan papayawhip coral);

sub Loader {
    return 'Bio::DB::SeqFeature::Store::BedLoader';
}

sub load_line {
    my $self = shift;
    my $line = shift;
    my $prefix = $self->strip_prefix;

    chomp $line;
    push @{$self->{conflines}},$line if $line =~ /^track/;
    $line =~ s/^$prefix// if $prefix;
    $self->loader->load_line($line);
}

sub finish_load {
    my $self = shift;

    my $line_count = shift;

    $self->set_status('creating database');
    $self->loader->finish_load();

    my $db        = $self->loader->store;
    my $conf      = $self->conf_fh;
    my $trackname = $self->track_name;
    my $dsn       = $self->dsn;
    my $backend   = $self->backend;

    $self->write_gff3($db,$dsn) if $backend eq 'memory';

    my $trackno   = 0;
    my $loadid    = $self->loadid;
    my $summary   = $line_count < TOO_SMALL_FOR_SUMMARY_MODE ? 'show summary = 0' : '';
    eval {
	$self->set_status('calculating summary statistics');
	$self->loader->build_summary;
    } unless $line_count < TOO_SMALL_FOR_SUMMARY_MODE;
    warn $@ if $@;

    $self->set_status('creating configuration');

    print $conf <<END;
[$loadid:database]
db_adaptor = Bio::DB::SeqFeature::Store
db_args    = -adaptor $backend
             -dsn     $dsn

#>>>>>>>>>> cut here <<<<<<<<
END
    ;

   my @lines = @{$self->{conflines}};  # correspond to a track line in the bed file

   unless (@lines) {
       my $track_label = $self->new_track_label;
       my $track_name  = $self->track_name;
       my $key         = $track_name;
       my $bgcolor     = $COLORS[rand @COLORS];
       my $glyph       = 'gene';
       my @types       = $self->loader->loaded_types;
       my $category = $self->category;
       print $conf <<END;
[$track_label]
database = $loadid
category = $category
glyph    = $glyph
feature  = @types
key      = $key
decorate_introns = 1
thin_utr = 1
utr_color= $bgcolor
fgcolor  = $bgcolor
bgcolor  = $bgcolor
$summary

END
   }   

   for my $track (@lines) {
       my %options    = $self->loader->parse_track_line($track);
       my $track_label = $self->new_track_label;
       my $track_name  = $self->track_name;
       my $key        = $options{name};
       my $description= $options{description};
       my $glyph      = 'gene';
       $options{visibility} ||= 'pack';
       my $bump       = $options{visibility} eq 'dense' ? 0 
                      : $options{visibility} eq 'pack'  ? 1 
		      : $options{visibility} eq 'full'  ? 2
		      : 1;
       my $bgcolor    = $options{itemRGB}  ? 'featureRGB'
                       :$options{useScore} ? 'featureScore'
                       :$options{color} ? "rgb($options{color})" 
                       :$COLORS[rand @COLORS];

       print $conf <<END;
[$track_label]
database = $loadid
category = My Tracks:Uploaded Tracks:$track_name
glyph    = $glyph
feature  = mRNA:$key region:$key
key      = $key
citation = $description
decorate_introns = 1
thin_utr = 1
utr_color = $bgcolor
fgcolor  = $bgcolor
bump     = $bump
bgcolor  = $bgcolor
$summary

END
   }

}


1;
