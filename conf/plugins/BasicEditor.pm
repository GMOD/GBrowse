# $Id: BasicEditor.pm,v 1.5 2003-10-12 16:52:22 sheldon_mckay Exp $

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
use Bio::Graphics::Browser::GFFhelper;
use Bio::Graphics::Browser::Plugin;

use vars '$VERSION','@ISA';
$VERSION = '0.01';

@ISA = qw(Bio::Graphics::Browser::Plugin Bio::Graphics::Browser::GFFhelper);


####################################################################
# Edit this list IP addresses of trusted hosts for database access
####################################################################
my $ips = <<END;
END
####################################################################

sub name { 
    'Basic Feature Editor'
}

sub description {
  p("BasicEditor allows simple feature editing"),
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

# not used
#sub reconfigure {
# }

#sub config_defaults {
# }

sub configure_form {
    my $self = shift;
    my $segments = $self->segments;
    my $segment = $segments->[0];

    # is this a trusted host?
    if ( forbid() ) {
	return h1("Sorry, access to the database is not allowed from your location");
    }

    return 0 unless $segment;
    my $html = start_table() .
               Tr( {-class => 'searchtitle'}, 
		   th( { -colspan => 9 }, 
		       h2("Features in $segment", 
			  "(based on the " . 
			  a( { -href => "http://www.sanger.ac.uk/Software/formats/GFF/GFF_Spec.shtml",
                               -target => '_NEW' },
			  u( "GFF2 specification)" ) ) ) ) ) . 
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
        
	# massage the attributes
	pop @cell;
	my @att = ();
	my %att = $_->attributes;

	while ( my ($k, $v) = each %att ) {
	    next if uc $k eq uc $v;
	    $v = qq("$v") if $v =~ /\s+/ && $v !~ /\"/;
	    push @att, "$k $v"; 
        }
        
        my $class = $_->group->class;
        my $name  = $_->group->name;
        unshift @att, "$class $name" unless uc $class eq uc $name;	
        push @cell, join ' ; ', @att;
	
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

    if ( forbid() ) {
	print h1("Access not allowed from your location");
        exit;
    }

    $self->{ref} = $segment->ref;
    my $db = $self->database;    

    my $gff_in = $self->gff_builder || return 0;
    my $gff = $self->read_gff($gff_in);
    
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
