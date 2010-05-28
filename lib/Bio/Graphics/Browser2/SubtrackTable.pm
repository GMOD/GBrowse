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

# turn the unparsed rows into parsed elements
# data structure = id => { index     => #sort position,
#                          selected  => boolean,
#                          fields    => [field1,field2,field3...] }
sub elements {
    my $self = shift;
    return $self->{_elements} if exists $self->{_elements};
    my $index = 0;
    my %elements;

    my $rows  = $self->rows;
    for my $r (@$rows) {
	my @data   = @$r;
	my @fields      = grep {!/^[=*]/}        @data;
	my ($id)        = grep {length} map {/^=([\d\w]+)/ && $1 } @data;
	my ($selected)  = grep {$_ eq '*'}       @data;
	$id           ||= join ';',@fields;
	$elements{$id} = { index    => $index++,
			   selected => $selected,
			   fields   => \@fields };
    }
    return $self->{_elements}=\%elements;
}

sub set_order {
    my $self          = shift;
    my $new_id_order  = shift;

    my $elements    = $self->elements;
    my %all_ids     = map {$_=>1} keys %$elements;
    my @ordered_ids = sort {$elements->{$a}{index}<=>$elements->{$b}{index}} keys %all_ids;

    my $idx = 0;
    my %seenit;

    # reorder the elements that are named on the list
    for my $e (@$new_id_order) {
	next unless $elements->{$e};  # uh oh
	$elements->{$e}{index} = $idx++;
	$seenit{$e}++;
    }

    # everything else keeps the default order from the config file
    for my $e (@ordered_ids) {
	$elements->{$e}{index} = $idx++ unless $seenit{$e};
    }
}

sub selection_table {
    my $self  = shift;
    my $render = shift;

    my $label     = $self->track_label;
    my $key       = $self->track_key || $label;
    my @selectors = $self->selectors;
    my $elements  = $self->elements;
    my (@popups,@sort_type,@boolean);

    my $table_id = "${label}_subtrack_id";

    # create the filter popups
    # by getting possible values for each selector
    for (my $i=0;$i<@selectors;$i++) {
	my %seenit;
	my @v       = sort grep {!$seenit{$_}++} map {$elements->{$_}{fields}[$i]} keys %$elements;

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

	$sort_type[$i] = $is_numeric && !$is_boolean ? 'table-sortable:numeric'
	                                             : 'table-sortable:default';
	
    }
    my @table_rows;
    push @table_rows,TR(th({-colspan=>$#selectors+2},"Select $key Subtracks"));
    push @table_rows,TR(     th({-class=>'table-sortable:numericdesc'},'Select'),
			map {th({-class=>"filterable $sort_type[$_]"},$selectors[$_][0])} (0..$#selectors));
			
    push @table_rows,TR(th(a({-href    => 'javascript:void(0)',
			      -onClick => 'Table.checkAll(this,false)'},'All off'),
			   a({-href    => 'javascript:void(0)',
			      -onClick => 'Table.checkAll(this,true)'}, 'All on')),
			th(\@popups));

    my $thead = thead(@table_rows);

    @table_rows = ();

    for my $e (sort {$elements->{$a}{index}<=>$elements->{$b}{index}} keys %$elements) {
	my $r = $elements->{$e}{fields};
	my @row_class   = $elements->{$e}{selected} ? (-class=> "selected") : ();
	push @table_rows,
	       TR({@row_class,-id=>"track_select_$e"},
		   th(checkbox( -value    => +1,
				-class   => 'rowSelect',
				-checked => $elements->{$e}{selected},
				-onChange=> 'Table.checkSelect(this)')
		  ),
		   td([
		       map {$boolean[$_] ? $r->[$_] ?'Yes':'No'
				         : $r->[$_]}(0..$#$r)
		]));
    }
    my $tbody = tbody({-id=>$table_id,-class=>'sortable'},@table_rows);

    my $tbottom = div(button(-name=>$render->tr('Cancel'),
			     -onClick => 'Balloon.prototype.hideTooltip(1)'),
		      button(-name    => $render->tr('Change'),
			     -onclick => "Table.sendTableState(\$('$table_id'));Controller.rerender_track('$label',false,false);Balloon.prototype.hideTooltip(1);"));

    my $script = script({-type=>'text/javascript'},<<END);
Position.includeScrollOffsets = true;
Sortable.create('$table_id',
                {tag:     'tr',
                 ghosting: true,
		 onUpdate:function(a){Table.stripe(a,'alternate')}
                });
Table.auto();
END

    return table({-width => 800,
		  -class => "subtrack-table table-autosort:0 table-stripeclass:alternate",
		 },
		 $thead,$tbody,$tbottom).$script;
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

