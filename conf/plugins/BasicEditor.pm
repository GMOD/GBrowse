# $Id: BasicEditor.pm,v 1.7 2003-10-13 18:58:51 sheldon_mckay Exp $

=head1 NAME

Bio::Graphics::Browser::Plugin::BasicEditor -- a plugin to edit GFF features 

=head1 SYNOPSIS

This modules is not used directly

=head1 DESCRIPTION

This plugin allows basic editing of features in the GFF database. It is just for 
demonstration purposes until it is properly secured against unauthorized 
database access.  Edit the list of allowed hosts in this module to
specify who is allowed to edit features

The database user specified in the configuration file must have sufficient 
privileges to delete and insert data.  See the gbrowse tutorial
for information on how to set this up.

The features contained in the current segment are dumped as GFF2 into a form
where the fields can be edited directly (except the reference sequence field).
The edited features are then loaded into the database after all features in the
segment's coordinate range are removed (except the reference component if one exists).

=head1 FEEDBACK

See the GMOD website for information on bug submission http://www.gmod.org.

=head1 AUTHOR - Sheldon McKay

Email smckay@bcgsc.bc.ca

=head1 CONTRIBUTORS

=cut

package Bio::Graphics::Browser::Plugin::BasicEditor;

use strict;
use CGI qw/:standard/;
use CGI::Carp qw/fatalsToBrowser/;
use Bio::Graphics::Browser::Plugin;
use Bio::Graphics::Browser::GFFhelper;

use vars qw/ $VERSION @ISA $ROLLBACK /;
$VERSION = '0.2';

@ISA = qw / Bio::Graphics::Browser::Plugin 
            Bio::Graphics::Browser::GFFhelper /;


####################################################################
# Edit this line to specify the rollback file location
# Comment it out to turn off rollbacks
####################################################################
# $ROLLBACK = '/tmp/';
####################################################################


####################################################################
# List IP addresses of trusted hosts for database access
# Adding an IP address will turn security on
####################################################################
my $ips = <<END;
END
####################################################################

sub name { 
    'Basic Feature Editor'
}

sub description {
  p("BasicEditor allows simple feature editing within gbrowse"),
  p("This plugin was written by Sheldon McKay");
}

sub type {     
     'annotator'
}

sub mime_type {
    'text/html'
}

# just use the plugin name for the plugin menu
sub verb {
    ' '
}


sub reconfigure {
    my $self = shift;
    my $conf = $self->configuration;
    $conf->{rb_id} = $self->config_param('rb_id');
}

sub config_defaults {
    { rb_id => undef }
}

sub configure_form {
    my $self = shift;
    my $segments = $self->segments;
    my $segment = $segments->[0];

    # is this a trusted host?
    if ( forbid() ) {
	return h1("Sorry, access to the database is not allowed from your location");
    }

    return 0 unless $segment;
    
    my $html;

    if ( $ROLLBACK ) {
	$self->{rb_loc} ||= $ROLLBACK;
	my $msg = "Selecting a rollback will override feature editing and " . 
	          "restore a previous state for segment $segment";
        $html = $self->rollback_form($msg) . 
	        '<input type="submit" name="plugin_action" value="Configure" />' . 
                br . br . "\n";
    }    

    $html .= start_table() .
	     Tr( {-class => 'searchtitle'}, 
		th( { -colspan => 9 }, 
		   "Features in $segment (based on the " . 
		      a( { -href => "http://www.sanger.ac.uk/Software/formats/GFF/GFF_Spec.shtml",
			   -target => '_NEW' },
		      u( "GFF2 specification)" ) ) ) ) . 
	       $self->build_form($segment) .
	       end_table();
}

sub build_form {
    my ($self, $segment) = @_;
    my $form = '';
    my $feat_count = 0;
    
    my @feats = ();
   
   # list all of the features to be deleted
   # must be inside of the range 
   for ( $segment->features ) {
	next if $_->start < $segment->start ||
                # source feature off by one error?
	        $_->stop  > $segment->stop + 1;

	push @feats, $_;
    }

    # try to put the features in a sensible order 
    # this is biased toward gene containment hierarchies
    @feats = sort { $a->start <=> $b->start or
		    $b->stop  <=> $a->stop  or
                    $a->gff_string cmp $b->gff_string } @feats;

    my %size = $self->set_cell_size(@feats);
    
    my $row = "<tr class=searchtitle>\n";
    $row .= th( [ qw/Delete Source Feature Start Stop Scr Str Phs Attribute/ ] ); 

    for ( @feats ) {
	next if $_->method =~ /component/i;
	$feat_count++;
	my $cellcount = 0;
	my @cell = split /\t/, $_->gff_string;

        # controlled vocabulary for Target
	$cell[8]  =~ s/Target \"?([^\"]+)\"? (\d+) (\d+)/Target "$1" ; tstart $2 ; tend $3/;

        # column 9 must be defined
        $cell[8] ||= ' ';

	$row .= "\n<tr class=searchdata valign=top>\n";
        my $del_name = 'BasicEditor.delete' . $feat_count;
        $row .= td( "<input type=checkbox name=$del_name>" ) . "\n";	
	
	for my $cell ( @cell  ) {
            next if ++$cellcount == 1;
	    $row .= td( textfield( -name  => 'BasicEditor.feature' . $feat_count,
				   -value => $cell,
				   -size  => $size{$cellcount} + 1 )) . "\n";
	}
        
        $row .= "</tr>\n";
    }
    
    # add some empty records for new features
    for ( 1..5 ) {
        $feat_count++;
        $row .= "\n<tr class=searchdata valign=top>\n" . 
                td( font( { -color => 'red' }, 'New' ) ) . "\n";
        for my $cell ( 2..9 ) {
            $row .= td( textfield( -name  => 'BasicEditor.feature' . $feat_count,
                                   -size  => $size{$cell} + 1 )) . "\n";
        }
    }

    $row;
}

sub set_cell_size {
    my ($self, @feats) = @_;
    
    my %max = ();
    
    for my $f ( @feats ) {
	my $count = 0;
	my @cells  = split "\t", $f->gff_string;
	
	for my $c ( @cells ) {
	    $count++;
	    my $len = length $c;
	    $max{$count} = $len if $len > $max{$count};
	}
    }

    $max{9} = 70;
    %max;
}


sub annotate {
    my ($self, $segment ) = @_;
    my $conf = $self->configuration;
    my $rollback = $conf->{rb_id};

    if ( forbid() ) {
	print h1("Access not allowed from your location");
        exit;
    }

    my $gff;
    my $db = $self->database;

    if ( $rollback ) {
	$self->{rb_loc} ||= $ROLLBACK;
	$self->save_state($segment) if $ROLLBACK;
	$gff = $self->rollback($rollback);
    }
    else {
	$self->{ref} = $segment->ref;
	my $gff_in = $self->gff_builder || return 0;
	$gff = $self->read_gff($gff_in);
    }    

    my @killme = ();
    
    # delete contained feature (except the reference component)
    for ( $segment->features ) {
        next if $_->start < $segment->start;
	next if $_->stop  > ($segment->stop + 1);
	next if $_->method =~ /component/i;
	push @killme, $_;
    }
    my $killed = $db->delete_features(@killme);

    my $fh = IO::String->new($gff);
    my $result = $db->load_gff($fh);

    unless ( $result ) {
        print h1("Problem loading features for $segment"),
	      h1(pre($gff));
        exit;
    }
    
    return 0;

}

sub gff_builder {
    my $self = shift;
    my $gff;
    
    for (param()) {
        next unless /feature/;
        my ($num) = /feature(\d+)/;
        next if param('BasicEditor.delete' . $num) || !param($_);
        my @text = param($_);
        
        # is it valid gff?
        if ( !$self->check_gff(\@text) ) {
	    print h1("Error: bad GFF format:"),
	          b( pre( join "\t", @text ) );
	    exit;
	} 

        unshift @text, $self->{ref};
        $gff .= ( join "\t", @text ) . "\n";
    }	
    $gff;
}

sub check_gff {
    my ($self, $gff) = @_;

    # user gets a pass on empty score, strand and phase fields
    for ( 4..6 ) { $gff->[$_] ||= '.' }

    # bet we have to draw the line somewhere...
    return 0 if $gff->[0] !~ /\w+/     || $gff->[1] !~ /\w+/;
    return 0 if $gff->[2] !~ /^-?\d+$/ || $gff->[3] !~ /^-?\d+$/;
    return 0 if $gff->[4] !~ /\d+|\.+/ || $gff->[6] !~ /\d|\./;
    return 0 if $gff->[5] !~ /^(\+|-|0|\.)+$/;

    1;
}

sub forbid {
    my $self = shift;
    $ips || return 0;
    my $fatal = shift;
    my $host = remote_addr();

    return $ips =~ /$host/m ? 0 : 1;

}

1;
