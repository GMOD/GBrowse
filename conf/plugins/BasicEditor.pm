# $Id: BasicEditor.pm,v 1.18 2004-03-12 15:16:23 sheldon_mckay Exp $

=head1 NAME

Bio::Graphics::Browser::Plugin::BasicEditor -- a plugin to edit GFF features 

=head1 SYNOPSIS

This modules is not used directly

=head1 DESCRIPTION

This plugin allows basic editing of features in the GFF database. 


The database user specified in the configuration file must have
sufficient privileges to delete and insert data.  See the gbrowse
tutorial for information on how to set this up.

The features contained in the current segment are dumped as GFF3
into a form where the fields can be edited directly (except the 
reference sequence field).  The edited features are then loaded 
into the database after all features in the segment's coordinate 
range are removed

=head1 FEEDBACK

See the GMOD website for information on bug submission http://www.gmod.org.

=head1 AUTHOR - Sheldon McKay

Email smckay@bcgsc.bc.ca

=head1 CONTRIBUTORS

=cut

package Bio::Graphics::Browser::Plugin::BasicEditor;

use strict;
use CGI qw/:standard *table unescape /;
use CGI::Carp qw/fatalsToBrowser/;
use Bio::Graphics::Browser::Plugin;
use Bio::Graphics::Browser::GFFhelper;

use vars qw/ $VERSION @ISA $ROLLBACK /;
$VERSION = '0.3';

@ISA = qw / Bio::Graphics::Browser::Plugin 
            Bio::Graphics::Browser::GFFhelper /;


####################################################################
# Edit this line to specify the rollback file location
# Comment it out to turn off rollbacks
####################################################################
$ROLLBACK = '/tmp/';
####################################################################


####################################################################
# List IP addresses of trusted hosts for database access
# Adding an IP address will turn security on
####################################################################
my $ips = <<END;
END
####################################################################

sub name { 
    'Edit Features'
}

sub description {
  p("BasicEditor allows simple feature editing within gbrowse"),
  p("This plugin was written by Sheldon McKay");
}

sub type {     
     'dumper'
}

sub mime_type {
    'text/html'
}

# just use the plugin name for the plugin menu
sub verb {
    ' '
}

# no persistent paramaters to be saved between sessions
#sub reconfigure {
#}
#sub config_defaults {
#}

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
	          "restore an archived feature set";

        $html = $self->rollback_form($msg, $segment->ref);
        
	my $button = qq(\n<input type="submit" name="plugin_action" value="Go">\n);
        $html =~ s|</a>|$& $button|m; 
        $html .= br . "\n";
    }    
    
    $html .= start_table() .
	     Tr( {-class => 'searchtitle'}, 
		th( { -colspan => 9 }, 
		   "Features in $segment (based on the " . 
		      a( { -href => "http://song.sourceforge.net/gff3.shtml",
			   -target => '_NEW' },
		      u( "GFF3 specification)" ) ) ) ) . 
	       $self->build_form($segment) .
	       end_table();

    # ensure that this page is loaded before the database update
    # can be performed
    $html .= hidden( -name    => $self->config_name('configured'),
		     -value   => 1 );

}

sub build_form {
    my ($self, $segment) = @_;
    my $form = '';
    my $feat_count = 0;
    my @feats = $self->contained_feats($segment); 

    # try to put the features in a sensible order 
    # this is biased toward gene containment hierarchies
    @feats = sort { $a->start <=> $b->start or
    		    $b->stop  <=> $a->stop  or
                    $a->name  cmp $b->name  or
		    $a->gff_string cmp $b->gff_string } @feats;

    my %size = $self->set_cell_size(@feats);
    
    my $row = "<tr class=searchtitle>\n";
    $row .= th( [ qw/Delete Source Feature Start Stop Scr Str Phs Attribute/ ] ); 

    for ( @feats ) {
	#next if $_->method =~ /component/i;
	$feat_count++;

        # use GFF3 dialect
	$_->version(3);
	my $cellcount = 0;
	my @cell = split /\t/, $_->gff_string;
	
        # human-readable attributes
	$cell[8] = unescape($cell[8]);

        # a bit of containment hierarchy tweaking...
	if ( $_->primary_tag ne 'mRNA' && $cell[-1] =~ /ID=mRNA:/ ||
             $_->primary_tag ne 'gene' && $cell[-1] =~ /ID=gene:/ ) {
	    $cell[-1] =~ s/ID/Parent/;
	}

        # column 9 must be defined
        $cell[8] ||= ' ';

	$row .= "\n<tr class=searchdata valign=top>\n";
        my $del_name = 'BasicEditor.delete' . $feat_count;
        $row .= td( "<input type=checkbox name=$del_name>" ) . "\n";	
	
	for my $cell ( @cell  ) {
            next if ++$cellcount == 1;
	    $cell =~ s/\"\"/\"/g;
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
	    $max{$count} ||= 1;
	    my $len = length $c || 1;
	    $max{$count} = $len if $len > $max{$count};
	}
    }

    $max{9} = 70;
    %max;
}


sub dump {
    my ($self, $segment ) = @_;
    return unless $segment;
    my $db = $self->database;
    my $rollback;

    # go to editor if the 'Dump' button was hit by mistake
    unless ( $self->config_param('configured') ) {
        print h2( font( { -color => 'slateblue' }, 
		  'One moment; redirecting to feature editor...') );
        $self->load_page;
    }


    # look for a rollback request. We do not want this to persist,
    # so the rb_id parameter is not saved in the configuration
    if ( $ROLLBACK ) {
	$rollback = $self->config_param('rb_id');
	$self->{rb_loc} = $ROLLBACK;
 	$self->save_state($segment);
    }

    if ( forbid() ) {
	print h1("Access not allowed from your location");
        exit;
    }

    my $gff;

    if ( $rollback ) {
	$gff = $self->rollback($rollback);
        # re-define the segment to the coordinate range of the cached GFF
	$self->get_range($gff);
	$segment = $db->segment( -name  => $self->ref,
				 -start => $self->start,
				 -stop  => $self->end );
    }
    else {
	$self->{ref} = $segment->ref;
	$gff  = $self->build_gff || return 0;
	$self->get_range($gff);
    }

    $gff = $self->gff_header(3,1) . "\n$gff";

    my @killme = $self->contained_feats($segment);

    my $killed = $db->delete_features(@killme);

    my $fh = IO::String->new($gff);
    my $result = $db->load_gff($fh);

    unless ( $result ) {
        print h1("Problem loading features for $segment"), pre($gff);
        exit;
    }
    
    $self->load_page($gff);    

    return 0;
}

sub load_page {
    my ($self, $gff) = @_;
    my $conf = $self->configuration;
    my @params;
    my $url = self_url();
    
    unless ( $gff ) {
        $url =~ s/plugin_action=Go/plugin_action=Configure.../;
	print body( { -onLoad => "window.location='$url'" } );
        return 0;
    }
    
    $self->get_range($gff);
    my $name = $self->refseq. ':';
    $name .= $self->start . '..' . $self->end;
    $url =~ s/\?.+$//g;

    print start_form( -name   => 'f1',
                      -method => 'POST',
                      -action => $url );

    print qq(<input type=hidden name=name value="$name">);
    print body( { -onLoad => "document.f1.submit()" } );
}


sub build_gff {
    my $self = shift;
    my $gff;
    
    for ( param() ) {
        next unless /feature/;
        my ($num) = /feature(\d+)/;
        next if $self->config_param('delete' . $num) || !param($_);
        my @text = param($_);
        $text[8] = $self->_escape($text[8]);
        
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

    # but we have to draw the line somewhere...
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

# deals with segment edge-effects
sub contained_feats {
    my $self    = shift;
    my $segment = shift;
    my $seq = $self->start ? $self : $segment;
    grep {
        $_->start >= $seq->start - 1 &&
        $_->end   <= $seq->end   + 1 &&
	$_->method !~ /component/i
    } $segment->features;
}

1;
