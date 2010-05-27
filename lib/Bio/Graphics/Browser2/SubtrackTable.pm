package Bio::Graphics::Browser2::SubtrackTable;
use strict;
use warnings;
use Carp 'croak';
use Bio::SeqFeatureI;
use CGI ':standard';

sub new {
    my $class = shift;
    my %args  = @_;

    # List of dimensions with instructions on how to pull them out of features.
    # [['Antibody','name'],['Confirmed','has_tag','confirmed'],['Stage','tag_value','stage']...]
    my $selectors = $args{-columns} or croak "-columns argument required";  

    # List of valid combinations of features.
    # [['H3K4me3' ,1,'E0-4h',23],['H3K4me3', 1, 'E4-48', 26],....]
    my $rows      = $args{-rows}    or croak "-rows argument required";

    # track label.
    my $label     = $args{-label}   or croak "-label argument required";

    # track key
    my $key       = $args{-key};


    return bless {
	selectors => $selectors,
	rows      => $rows,
	label     => $label,
	key       => $key,
    },ref $class || $class;
}

sub track_label { shift->{label} }
sub track_key   { shift->{key}   }

sub selectors {
    my $self = shift;
    return @{$self->{selectors}};
}

sub rows {
    my $self = shift;
    return $self->{rows};
}

sub selection_table {
    my $self  = shift;

    my $label     = $self->track_label;
    my $key       = $self->track_key || $label;
    my @selectors = $self->selectors;
    my $rows      = $self->rows;
    my (@popups,@sort_type,@boolean);

    # create the filter popups
    # by getting possible values for each selector
    for (my $i=0;$i<@selectors;$i++) {
	my %seenit;
	my @v       = sort grep {!$seenit{$_}++} map {$_->[$i]} @$rows;

	my $is_numeric = 1;
	for my $v (@v) {
	    $is_numeric &&= $v =~ /^[\d+.Ee-]$/;
	}
	my $is_boolean = $selectors[$i][1] eq 'has_tag';
	if ($is_boolean) {
	    @v = map {$_ ? 'Yes' : 'No'} @v;
	}

	unshift @v,'';
	$popups[$i] = popup_menu(-onChange => 'Table.filter(this,this)',
				 -name     => "$selectors[$i][0]-select",
				 -values   => \@v,
				 -labels   => {''=>'All'});

	$boolean[$i]   = $is_boolean;

	$sort_type[$i] = $is_numeric &&!$is_boolean ? 'table-sortable:numeric'
	                                            : 'table-sortable:default';
	
    }
    my @table_rows;
    push @table_rows,TR(th({-colspan=>$#selectors+2},"Select $key Subtracks"));
    push @table_rows,TR({-onClick=>'Table.sendTableState(this)'},
			     th({-class=>'table-sortable:default'},'Select'),
			map {th({-class=>"filterable $sort_type[$_]"},$selectors[$_][0])} (0..$#selectors));
			
    push @table_rows,TR(th(a({-href    => 'javascript:void(0)',
			      -onClick => 'Table.checkAll(this,false)'},'All off'),
			   a({-href    => 'javascript:void(0)',
			      -onClick => 'Table.checkAll(this,true)'}, 'All on')),
			th(\@popups));

    my $thead = thead(@table_rows);

    @table_rows = ();

    for my $r (@$rows) {
	push @table_rows,
	       TR(
		   th(checkbox(-value=>-1,-class=>'rowSelect',-onChange=>'Table.checkSelect(this)')),
		   td([
		       map {$boolean[$_] ? $r->[$_] ?'Yes':'No'
				         : $r->[$_]}(0..$#$r)
		]));
    }
    my $tbody = tbody({-id=>"${label}_subtrack_id",-class=>'sortable'},@table_rows);
    my $script = script({-type=>'text/javascript'},<<END);
Position.includeScrollOffsets = true;
Sortable.create('${label}_subtrack_id',
                {tag:     'tr',
                 ghosting: true,
                 scroll:   '${label}_subtrack_scroll',
                 onUpdate:function(a){Table.stripe(a,'alternate');
                                      Table.sendTableState(a)}
                });
END

    return div({-class=>'subtrack_table',-id=>"${label}_subtrack_scroll"},
	       table({-class => "subtrack-table table-autosort:0 table-stripeclass:alternate"},
		     $thead,$tbody)).$script;
}

# turn array of features into an array of row identifiers
# the identifiers will be separated by semicolons and will
# follow the order given by the selectors, for example:
#     'H3K4me3;1;E0-4h'
#     'H3K9me3;1;E0-4h'
#     'H3K9me3;1;E4-8h'
#     'H3K9me1;0;E0-4h'

sub features_to_matchstr {
    my $self     = shift;
    my @features = @_;

    my $transform = $self->_transform;
    my @transform = map {$transform->($_)} @features;
    return \@transform;
}

sub _transform {
    my $self = shift;
    return $self->{_transform} if exists $self->{_transform};

    my @selectors = $self->selectors();
    my $sub = "sub { my \$f = shift;\nmy \@d;\n";
    for my $s (@selectors) {
	my ($name,$op,$val) = @$s;
	if ($op eq 'has_tag') {
	    $sub .= "push \@d,\$f->has_tag('$val')?'Yes':'No';\n";
	} elsif ($op eq 'tag_value') {
	    $sub .= "push \@d, \$f->has_tag('$val')?(\$f->get_tag_values('$val'))[0]:'';\n";
	} else {
	    $sub .= "eval{push \@d, \$f->$op()};\n";
	}
    }
    $sub .= "return join(';',\@d);}\n";
    my $transform =  eval $sub;
    warn $@ unless $transform;
    return $self->{_transform} = $transform;
}

1;

