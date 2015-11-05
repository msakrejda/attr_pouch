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


### Usage

AttrPouch allows you to designate a "pouch" database `hstore` field
that provides schema-less storage for any `Sequel::Model`
object. Within this pouch, you define additional fields that behave
largely like standard Sequel fields (i.e., as if they were backed by
their own database columns), but are all in fact stored in the pouch:

```ruby
class User < Sequel::Model
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
  pouch(:preferences) do
	field :favorite_color, default: 'puce'
  end
end

ursula = User.create(name: 'ursula')
ursula.favorite_color # 'puce'
```

#### Types

AttrPouch supports per-type serializers and deserializers to allow
Ruby objects to be handled transparently as field values.

AttrPouch comes with a number of built-in encoders and decoders for
some common data types, and these are specified either directly using
Ruby classes or via symbols representing an encoding mechanism. The
simple built-in types are `String`, `Integer`, `Float`, `Time`,
`:bool` (since Ruby has no single class representing a boolean type).

```ruby
class User < Sequel::Model
  pouch(:preferences) do
    field :favorite_color, String
    field :lucky_number, Integer
    field :smoker?, :bool
  end
end
```

You can also override these built-ins or register entirely new types.

```ruby
AttrPouch.configure do |config|
  config.write(:obfuscated_string) do |field, value|
    value.reverse
  end
  config.read(:obfuscated_string) do |field, value|
    value.reverse
  end
end
```

Note that your encoder and decoder do have access to the field object,
which includes name, type, and any options you've configured in the
field definition.

When an encoder or decoder is specified via symbol, it will only work
for fields whose type is declared to be exactly that symbol. When
specified via class, it will also be used to encode and decode any fields whose declared type is a subclass of the encoder/decoder class.

This can be illustrated via the last built-in codec, for
`Sequel::Model` objects:

```ruby
class User < Sequel::Model
  pouch(:preferences) do
    field :bff, User
  end
end

alonzo = User.create(name: 'alonzo')
alonzo.update(bff: User[name: 'ursula'])
```

Even though the built-in encoder is specified for just
`Sequel::Model`, it can handle the `bff` field above with no
additional configuration because `User` descends from `Sequel::Model`.

If the field type is not specified, it is inferred from the field
definition. The default mechanism only considers field names and
infers types as follows:

 * `Integer`: name starts with `num_` or ends in `_size` or `_count`
 * `Time`: name ends with `_at` or `_by`
 * `:bool`: name ends with `?`
 * `String`: anything else

If this is not suitable, you can register your own type inference
mechanism instead:

```ruby
AttrPouch.configure do |config|
  config.infer_type { |field| String }
end
```

The above just considers every field without a declared type to be a
`String`.

#### Schema requirements

AttrPouch requires a new storage field for each pouch added to a
model. It is currently designed for and tested with `hstore`. Consider
using a single pouch per model class unless you clearly need several
distinct pouches.

```ruby
Sequel.migration do
  change do
    alter_table(:users) do
      add_column :attrs, :hstore
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

Please follow the project's general coding style and open issues for
any significant behavior or API changes.

A pull request is understood to mean you are offering your code to the
project under the MIT License.


### License

Copyright (c) 2015 AttrPouch Contributors

MIT License. See LICENSE for full text.
