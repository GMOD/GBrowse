package Bio::DB::Tagger::Tag;
# $Id$

use Carp 'croak';
use overload
    '""'     => 'asString',
    'cmp'    => 'cmp',
    fallback => 1;

=head1 NAME

Bio::DB::Tagger::Tag -- Authored tags

=head1 SYNOPSIS

 use Bio::DB::Tagger::Tag;

 my $tag = Bio::DB::Tagger::Tag->new(-name   => 'venue',
                                     -value  => 'mermaid parade',
                                     -author => 'lincoln.stein@gmail.com');
 print $tag,"\n";          # use like a string
 print $tag->name,"\n";    # object interface
 print $tag->value,"\n";   # object interface
 print $tag->author,"\n";

=head1 DESCRIPTION

This is a simple object tag interface that provides string-like
objects that have authors assigned to them. For use in attributing
tags to authors in the L<Bio::DB::Tagger> module.

=head2 METHODS

=over 4

=item $tag = Bio::DB::Tagger::Tag->new(-name=>$tag,
                                       -author=>$author
                                      [,-value=> $value,
                                       ,-modified=>$timestamp]);

Create a new tag with the indicated value and author.

=cut

sub new {
    my $class  = shift;

    my %args       = @_;
    my $author     = $args{-author} || '';
    my $name       = $args{-name};
    my $value      = $args{-value};
    my $timestamp  = $args{-modified};
    croak "Usage: $class->new(-name=>'name' [,-value=>'tag value',-author=>'author'])"
	unless defined $name;
    return bless {
	name    => $name,
	value   => $value,
	author  => $author,
	modified=>$timestamp,
    },ref $class || $class;
}

=item $name = $tag->name

Return the tag's name.

=cut

sub name {
    shift->{name};
}

=item $value = $tag->value;

Return the tag's value.

=cut

sub value {
    shift->{value};
}

=item $timestamp = $tag->modified

Return the tag's modification timestamp.

=cut

sub modified {
    shift->{modified};
}

=item $author = $tag->author;

Return the tag's author

=cut

sub author {
    shift->{author};
}

=item $int = $tag->cmp($tag,$reversed)

Perform a string cmp() operation on another tag or a string.
If a string is provided, then operation is on tag name only.
If a tag is provided, then operation is on both tag and value.

=cut

sub cmp {
    my $self              = shift;
    my ($other,$reversed) = @_;

    my $name  = $self->name;
    my $value = $self->value;

    my $result;
    if (ref $other && $other->isa(__PACKAGE__)) {
	my $other_name  = $other->name;
	my $other_value = $other->value;
	$result = "${name}${value}" cmp "${other_name}${other_value}";
    } else {
	$result = $name cmp $other;
    }
    return $reversed ? -1*$result : $result;
}

=item $string = $tag->asString

Convert into a name:value string

=cut

sub asString {
    my $self              = shift;
    return $self->name;
}

=back

=head1 SEE ALSO

L<Bio::DB::Tagger>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2009 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut



1;

__END__
