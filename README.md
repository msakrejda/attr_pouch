[![Build Status](https://travis-ci.org/uhoh-itsmaciek/attr_pouch.svg)](https://travis-ci.org/uhoh-itsmaciek/attr_pouch)

# AttrPouch

Schema-less attribute storage plugin for Sequel
[Sequel](https://github.com/jeremyevans/sequel.git).


### Philosophy

Database schemas are great: they enforce data integrity and help
ensure that your data always looks like you expect it to. Furthermore,
indexing can dramatically speed up many types of complex queries with
a schema.

However, schemas can also get in the way: dozens of columns get to be
unwieldy with most database tools, and migrations to add and drop
columns can be difficult on large data sets.

Consequently, schema-less storage can be an excellent complement to
a rigid database schema: define a schema for the well-understood parts
of your data model, but augment it with

### Usage

```ruby
AttrPouch.configure do |config|
  config.write(:string) do |store, field, value|
    store[field.name] = value.reverse
  end
  config.read(:string) do |store, field|
    store[field.name].reverse
  end
end
```

```ruby
class Album
  pouch(:attrs) do
    field :foo, String, default: 'hello', required: true
  end
end
```

#### General schema changes

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
