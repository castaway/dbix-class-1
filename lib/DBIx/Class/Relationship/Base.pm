package DBIx::Class::Relationship::Base;

use strict;
use warnings;

use base qw/DBIx::Class/;

__PACKAGE__->mk_classdata('_relationships', { } );

=head1 NAME 

DBIx::Class::Relationship::Base - Inter-table relationships

=head1 SYNOPSIS

=head1 DESCRIPTION

This class provides methods to describe the relationships between the
tables in your database model. These are the "bare bones" relationships
methods, for predefined ones, look in L<DBIx::Class::Relationship>. 

=head1 METHODS

=head2 add_relationship

=head3 Arguments: ('relname', 'Foreign::Class', $cond, $attrs)

  __PACKAGE__->add_relationship('relname', 'Foreign::Class', $cond, $attrs);

The condition needs to be an SQL::Abstract-style representation of the
join between the tables. When resolving the condition for use in a JOIN,
keys using the psuedo-table I<foreign> are resolved to mean "the Table on the
other side of the relationship", and values using the psuedo-table I<self>
are resolved to mean "the Table this class is representing". Other
restrictions, such as by value, sub-select and other tables, may also be
used. Please check your database for JOIN parameter support.

For example, if you're creating a rel from Author to Book, where the Book
table has a column author_id containing the ID of the Author row:

  { 'foreign.author_id' => 'self.id' }

will result in the JOIN clause

  author me JOIN book book ON bar.author_id = me.id

You can specify as many foreign => self mappings as necessary. Each key/value
pair provided in a hashref will be used as ANDed conditions, to add an ORed
condition, use an arrayref of hashrefs. See the L<SQL::Abstract> documentation
for more details.

Valid attributes are as follows:

=over 4

=item join_type

Explicitly specifies the type of join to use in the relationship. Any SQL
join type is valid, e.g. C<LEFT> or C<RIGHT>. It will be placed in the SQL
command immediately before C<JOIN>.

=item proxy

An arrayref containing a list of accessors in the foreign class to create in
the main class. If, for example, you do the following:
  
  MyDB::Schema::CD->might_have(liner_notes => 'MyDB::Schema::LinerNotes', undef, {
    proxy => [ qw/notes/ ],
  });
  
Then, assuming MyDB::Schema::LinerNotes has an accessor named notes, you can do:

  my $cd = MyDB::Schema::CD->find(1);
  $cd->notes('Notes go here'); # set notes -- LinerNotes object is
                               # created if it doesn't exist
  
=item accessor

Specifies the type of accessor that should be created for the relationship.
Valid values are C<single> (for when there is only a single related object),
C<multi> (when there can be many), and C<filter> (for when there is a single
related object, but you also want the relationship accessor to double as
a column accessor). For C<multi> accessors, an add_to_* method is also
created, which calls C<create_related> for the relationship.

=back

=head2 register_relationship

=head3 Arguments: ($relname, $rel_info)

Registers a relationship on the class. This is called internally by
L<DBIx::Class::ResultSourceProxy> to set up Accessors and Proxies.

=cut

sub register_relationship { }

=head2 related_resultset($name)

  $rs = $obj->related_resultset('related_table');

Returns a L<DBIx::Class::ResultSet> for the relationship named $name.

=cut

sub related_resultset {
  my $self = shift;
  $self->throw_exception("Can't call *_related as class methods") unless ref $self;
  my $rel = shift;
  my $rel_obj = $self->relationship_info($rel);
  $self->throw_exception( "No such relationship ${rel}" ) unless $rel_obj;
  
  return $self->{related_resultsets}{$rel} ||= do {
    my $attrs = (@_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {});
    $attrs = { %{$rel_obj->{attrs} || {}}, %$attrs };

    $self->throw_exception( "Invalid query: @_" ) if (@_ > 1 && (@_ % 2 == 1));
    my $query = ((@_ > 1) ? {@_} : shift);

    my $cond = $self->result_source->resolve_condition($rel_obj->{cond}, $rel, $self);
    if (ref $cond eq 'ARRAY') {
      $cond = [ map { my $hash;
        foreach my $key (keys %$_) {
          my $newkey = $key =~ /\./ ? "me.$key" : $key;
          $hash->{$newkey} = $_->{$key};
        }; $hash } @$cond ];
    } else {
      foreach my $key (grep { ! /\./ } keys %$cond) {
        $cond->{"me.$key"} = delete $cond->{$key};
      }
    }
    $query = ($query ? { '-and' => [ $cond, $query ] } : $cond);
    $self->result_source->related_source($rel)->resultset->search($query, $attrs);
  };
}

=head2 search_related

  $rs->search_related('relname', $cond, $attrs);

Run a search on a related resultset. The search will be restricted to the
item or items represented by the L<DBIx::Class::ResultSet> it was called
upon. This method can be called on a ResultSet, a Row or a ResultSource class.

=cut

sub search_related {
  return shift->related_resultset(shift)->search(@_);
}

=head2 count_related

  $obj->count_related('relname', $cond, $attrs);

Returns the count of all the items in the related resultset, restricted by
the current item or where conditions. Can be called on a L<DBIx::Classl::Manual::Glossary/"ResultSet"> or a L<DBIx::Class::Manual::Glossary/"Row"> object.

=cut

sub count_related {
  my $self = shift;
  return $self->search_related(@_)->count;
}

=head2 new_related

  my $new_obj = $obj->new_related('relname', \%col_data);

Create a new item of the related foreign class. If called on a
L<DBIx::Class::Manual::Glossary/"Row"> object, it will magically
set any primary key values into foreign key columns for you. The newly
created item will not be saved into your storage until you call C<insert>
on it.

=cut

sub new_related {
  my ($self, $rel, $values, $attrs) = @_;
  return $self->search_related($rel)->new($values, $attrs);
}

=head2 create_related

  my $new_obj = $obj->create_related('relname', \%col_data);

Creates a new item, similarly to new_related, and also inserts the item's data
into your storage medium. See the distinction between C<create> and C<new>
in L<DBIx::Class::ResultSet> for details.

=cut

sub create_related {
  my $self = shift;
  my $rel = shift;
  my $obj = $self->search_related($rel)->create(@_);
  delete $self->{related_resultsets}->{$rel};
  return $obj;
}

=head2 find_related

  my $found_item = $obj->find_related('relname', @pri_vals | \%pri_vals);

Attempt to find a related object using its primary key or unique constraints.
See C<find> in L<DBIx::Class::ResultSet> for details.

=cut

sub find_related {
  my $self = shift;
  my $rel = shift;
  return $self->search_related($rel)->find(@_);
}

=head2 find_or_create_related

  my $new_obj = $obj->find_or_create_related('relname', \%col_data);

Find or create an item of a related class. See C<find_or_create> in
L<DBIx::Class::ResultSet> for details.

=cut

sub find_or_create_related {
  my $self = shift;
  return $self->find_related(@_) || $self->create_related(@_);
}

=head2 set_from_related

  $book->set_from_related('author', $author_obj);

Set column values on the current object, using related values from the given
related object. This is used to associate previously separate objects, for
example, to set the correct author for a book, find the Author object, then
call set_from_related on the book.

The columns are only set in the local copy of the object, call C<update> to set
them in the storage.

=cut

sub set_from_related {
  my ($self, $rel, $f_obj) = @_;
  my $rel_obj = $self->relationship_info($rel);
  $self->throw_exception( "No such relationship ${rel}" ) unless $rel_obj;
  my $cond = $rel_obj->{cond};
  $self->throw_exception( "set_from_related can only handle a hash condition; the "
    ."condition for $rel is of type ".(ref $cond ? ref $cond : 'plain scalar'))
      unless ref $cond eq 'HASH';
  my $f_class = $self->result_source->schema->class($rel_obj->{class});
  $self->throw_exception( "Object $f_obj isn't a ".$f_class )
    unless $f_obj->isa($f_class);
  $self->set_columns(
    $self->result_source->resolve_condition(
       $rel_obj->{cond}, $f_obj, $rel));
  return 1;
}

=head2 update_from_related

  $book->update_from_related('author', $author_obj);

As C<set_from_related>, but the changes are immediately updated onto your
storage.

=cut

sub update_from_related {
  my $self = shift;
  $self->set_from_related(@_);
  $self->update;
}

=head2 delete_related

  $obj->delete_related('relname', $cond, $attrs);

Delete any related item subject to the given conditions.

=cut

sub delete_related {
  my $self = shift;
  my $obj = $self->search_related(@_)->delete;
  delete $self->{related_resultsets}->{$_[0]};
  return $obj;
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

