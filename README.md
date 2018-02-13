[![Build Status](https://travis-ci.org/uhoh-itsmaciek/attr_pouch.svg)](https://travis-ci.org/uhoh-itsmaciek/attr_pouch)

# AttrPouch

Schema-less attribute storage plugin for
[Sequel](https://github.com/jeremyevans/sequel.git).


### Philosophy

Database schemas are great: they enforce data integrity and help
ensure that your data always looks like you expect it to. Furthermore,
indexing can dramatically speed up many types of complex queries with
a schema.

However, schemas can also get in the way: dozens of columns get to be
unwieldy with most database tools, and migrations to add and drop
columns can be difficult on large data sets.

Consequently, schema-less storage can be an excellent complement to a
rigid database schema: you can define a schema for the well-understood
parts of your data model, but augment it with schema-less storage for
the parts that are in flux or just awkward to fit into the relational
model.

### Installation

Add `attr_pouch` to your `Gemfile`:

```ruby
gem 'attr_pouch'
```

Then run `bundle install`.

### Usage

AttrPouch allows you to designate a "pouch" database field (of type
`jsonb`, `hstore`, or `json`) that provides schema-less storage for
any `Sequel::Model` object. Within this pouch, you can define
sub-fields that behave largely like standard Sequel fields (i.e., as
if they were backed by their own database columns), but are all in
fact stored in the pouch:

```ruby
class User < Sequel::Model
  include AttrPouch

  pouch(:preferences) do
    field :theme
    field :autoplay_videos?
  end
end

bob = User.create(name: 'bob')
bob.theme = 'gothic'
bob.autoplay_videos = false
bob.save_changes
bob.update(theme: 'ponies!', autoplay_videos: false)
```

Note that if a field name ends in a question mark, its setter is
defined with the trailing question mark stripped.

Because there is no schema defined for these fields, changes to the
pouch definition do not require a database migration. You can add
and remove fields with just code changes.

#### Defaults

Fields are required by default; attempting to read a field that has
not been set will raise `AttrPouch::MissingRequiredFieldError`. They
can be marked as optional by providing a default:

```ruby
class User < Sequel::Model
  include AttrPouch

  pouch(:preferences) do
    field :favorite_color, default: 'puce'
  end
end

ursula = User.create(name: 'ursula')
ursula.favorite_color # 'puce'
```

#### Types

AttrPouch supports per-type serializers and deserializers to allow any
Ruby objects to be handled transparently as field values (as long as
they can be serialized and deserialized in some fashion).

AttrPouch comes with a number of built-in encoders and decoders for
some common data types, and these are specified either directly using
Ruby classes or via symbols representing an encoding mechanism. The
simple built-in types are `String`, `Integer`, `Float`, `Time`, and
`:bool` (since Ruby has no single class representing a boolean type,
`attr_pouch` uses a symbol to stand in as a "logical" type here).

```ruby
class User < Sequel::Model
  include AttrPouch

  pouch(:preferences) do
    field :favorite_color, type: String
    field :lucky_number, type: Integer
    field :gluten_free?, type: :bool
  end
end
```

You can override these built-ins or register entirely new types:

```ruby
AttrPouch.configure do |config|
  config.encode(:obfuscated_string) do |field, value|
    value.reverse
  end
  config.decode(:obfuscated_string) do |field, value|
    value.reverse
  end
end
```

Note that your encoder and decoder do have access to the field
definition object, which includes name, type, and any options you've
configured in the field definition. Option names are not checked by
`attr_vault`, so custom decoder or encoder options are possible.

When an encoder or decoder is specified via symbol, it will only work
for fields whose type is declared to be exactly that symbol. When
specified via class, it will also be used to encode and decode any
fields whose declared type is a subclass of the encoder/decoder class.

This can be illustrated via the last built-in codec, for
`Sequel::Model` objects:

```ruby
class User < Sequel::Model
  include AttrPouch

  pouch(:preferences) do
    field :bff, type: User
  end
end

alonzo = User.create(name: 'alonzo')
alonzo.update(bff: User[name: 'ursula'])
```

Even though the built-in encoder is specified for just `Sequel::Model`
(no custom encoder was specified for `User` here), it can handle the
`bff` field above with no additional configuration because `User`
descends from `Sequel::Model`.

If the field type is not specified, it is inferred from the field
definition. The default mechanism only considers the field name and
infers types as follows:

 * `Integer`: name starts with `num_` or ends in `_size` or `_count`
 * `Time`: name ends with `_at` or `_by`
 * `:bool`: name ends with `?`
 * `String`: anything else

If this is not suitable, you can register your own "type inference"
mechanism instead:

```ruby
AttrPouch.configure do |config|
  config.infer_type { |field| String }
end
```

The above just considers every field without a declared type to be a
`String`.

#### Deletable fields

Fields can be marked `deletable`, which will generate two deleter
methods for them:

```ruby
class User < Sequel::Model
  include AttrPouch

  pouch(:preferences) do
    field :proxy_address, deletable: true
  end
end

karen = User.create(name: 'karen')
karen.update(proxy_address: '10.11.12.13:8001')
karen.delete_proxy_address # note this does not save the object
karen.reload
karen.proxy_address # still '10.11.12.13:8001'; we never saved
karen.delete_proxy_address! # or call #save or #save_changes after a delete
karen.proxy_address # now it's gone
```

Deletable fields are automatically given a default of `nil` if no
other default is present; reading a deletable field does not raise an
error.

N.B.: You can still delete fields without this flag by deleting their
corresponding keys directly from the underlying storage column,
flagging the field as modified (to ensure Sequel knows the field has
changed, since the object reference it holds does *not* change when
the object itself is modified). You can also set the value to `nil`
explicitly which, while not semantically identical, can be sufficient.

#### Immutable fields

Fields are mutable by default but can be flagged immutable to reject
updates once an initial value has been set:

```ruby
class User < Sequel::Model
  include AttrPouch

  pouch(:preferences) do
    field :lucky?, mutable: false
  end
end

abbas = User.create(name: 'abbas', lucky: true)
abbas.lucky?        # true
abbas.lucky = false # raises ImmutableFieldUpdateError
```

#### Renaming fields

Fields can be renamed by providing a previous name or an array of
previous names under the `was` option.

```ruby
class User < Sequel::Model
  include AttrPouch

  pouch(:preferences) do
    field :tls?, was: :ssl?
    field :instabul?, was: %i[constantinople? byzantion?]
  end
end

nils = User[name: 'nils'] # in db we have `{ ssl?: true, byzantion?: true }`
nils.tls?                 # true
nils.istanbul?            # true
```

Note that no direct accessors are defined for the old names, and if
the value is updated, it is written under the new name and any old
values in the pouch are deleted:

```ruby
nils.byzantion?       # raises NoMethodError
nils.istanbul = false
nils.tls?             # true
nils.instanbul?       # false
nils.save_changes     # now in db as `{ tls?: true, instanbul?: false }`
```

#### Raw value access

Any field can be accessed directly, bypassing the encoder and decoder,
by specifying the `raw_field` option to provide the name of the setter
and getter that will be created to manipulate the underlying value
directly. Required fields are still required when read via
`raw_field`, and immutable fields are still immutable, but if a
`default` is set, the raw value will be `nil`, rather than the default
itself, to allow the user to distinguish between a field value equal
to the default and an absent field value deferring to the default:

```ruby
class User < Sequel::Model
  include AttrPouch

  pouch(:preferences) do
    field :bff, type: User, raw_field: :bff_id
    field :arch_nemesis, type: User, raw_field: :nemesis_id,
          default: User[name: 'donald']
  end
end

alonzo = User.create(name: 'alonzo')
alonzo.update(bff: User[name: 'ursula'])
alonzo.bff_id # Ursula's user id
alonzo.arch_nemesis # the User object representing the 'donald' record
alonzo.nemesis_id   # nil
```

Raw fields also obey the `was` option for renames, as above. If the
raw field value is updated, values present under any of the `was` keys
will be deleted.


### Dataset querying

AttrPouch provides a dataset method to simplify querying pouch
contents. The interface is similar to querying first-class columns:

```ruby
class User < Sequel::Model
  include AttrPouch

  pouch(:preferences) do
    field :bff, type: User
    field :favorite_color
  end
end

# match on multiple fields
User.where_pouch(:preferences, bff: User[name: 'georgia'], favorite_color: 'goldenrod').all
# match on multiple values
User.where_pouch(:preferences, favorite_color: [ 'gray', 'dark gray', 'black' ]).all
# check for nil value (or absence of key)
User.where_pouch(:preferences, bff: nil).all
```

Note that you can speed up your queries considerably by adding an
index. AttrPouch uses containment queries to implement dataset
querying, so you can use GIN indexes with both
[`hstore`](https://www.postgresql.org/docs/current/static/hstore.html#AEN160038)
and
[`jsonb`](https://www.postgresql.org/docs/current/static/datatype-json.html#JSON-INDEXING):

```ruby
Sequel.migration do
  up do
    execute <<-EOF
CREATE INDEX users_prefs_idx ON users USING gin (preferences);
EOF
  end
  down do
    execute <<-EOF
DROP INDEX users_prefs_idx;
EOF
  end
EOF
end
```

N.B.: For simplicity, AttrPouch treats the absence of a key and the
presence of a key with a `NULL` value the same when querying, which
means queries looking for `nil` values do not use the indexes.

Dataset queries are not supported for fields backed by columns of
type `json`.

### Schema

AttrPouch requires a new storage field for each pouch added to a
model. It is currently designed for and tested with `jsonb`, `hstore`,
and `json` (although `json`-format fields do not currently support
dataset querying, as per above). Consider using a single pouch per
model class unless you clearly need several distinct pouches.

```ruby
Sequel.migration do
  change do
    alter_table(:users) do
      add_column :preferences, :jsonb
    end
  end
end
```

### Contributing

Patches are warmly welcome.

To run tests locally, you'll need a `DATABASE_URL` environment
variable pointing to a database AttrPouch can use for testing. E.g.,

```console
$ createdb attr_pouch_test
$ DATABASE_URL=postgres:///attr_pouch_test bundle exec rspec
```

Please follow the project's general coding style and open issues
beforehand to discuss any significant behavior or API changes.

A pull request is understood to mean you are offering your code to the
project under the MIT License.


### License

Copyright (c) 2015 AttrPouch Contributors

MIT License. See LICENSE for full text.
