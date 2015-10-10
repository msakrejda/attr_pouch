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
  config.read(:string) do |value|
    value.reverse
  end
	
end
```

```ruby
class Album
  pouch_field: :attrs_unparsed
  pouch_attr :foo, :string, default: 'hello', required: false
end
```



### old attr_vault stuff below

#### General schema changes

AttrVault needs some small changes to your database schema. It
requires a key identifier column for each model that uses encrypted
fields, and a binary data column for each field.

Here is a sample Sequel migration for adding encrypted fields to
Postgres, where binary data is stored in `bytea` columns:

```ruby
Sequel.migration do
  change do
    alter_table(:diary_entries) do
      add_column :key_id, :uuid
      add_column :secret_stuff, :bytea
    end
  end
end
```


#### Encrypted fields

AttrVault needs some configuration in models as well. A
`pouch_keyring` attribute specifies a keyring in JSON (see the
expected format above). Then, for each field to be encrypted, include
a `pouch_attr` attribute with its desired attribute name. You can
optionally specify the name of the encrypted column as well (by
default, it will be the field name suffixed with `_encrypted`):

```ruby
class DiaryEntry < Sequel::Model
  pouch_keyring ENV['ATTR_VAULT_KEYRING']
  pouch_attr :body, encrypted_field: :secret_stuff
end
```

AttrVault will generate getters and setters for any `pouch_attr`s
specified.


#### Lookups

One tricky aspect of encryption is looking up records by known secret.
E.g.,

```ruby
DiaryEntry.where(body: '@SwiftOnSecurity is dreamy')
```

is trivial with plaintext fields, but impossible with the model
defined as above.

AttrVault includes a way to mitigate this. Another small schema change:

```ruby
Sequel.migration do
  change do
    alter_table(:diary_entries) do
      add_column :secret_digest, :bytea
    end
  end
end
```

Another small model definition change:

```ruby
class DiaryEntry < Sequel::Model
  pouch_keyring ENV['ATTR_VAULT_KEYRING']
  pouch_attr :body, encrypted_field: :secret_stuff,
    digest_field: :secret_digest
end
```

To be continued...

(storing digests is implemented, easy lookup by digest is not)

#### Migrating unencrypted data

If you have plaintext data that you'd like to start encrypting, doing
so in one shot can require a maintenance window if your data volume is
large enough. To avoid this, AttrVault supports online migration via
an "encrypt-on-write" mechanism: models will be read as normal, but
their fields will be encrypted whenever the models are saved. To
enable this behavior, just specify where the unencrypted data is
coming from:

```ruby
class DiaryEntry < Sequel::Model
  pouch_keyring ENV['ATTR_VAULT_KEYRING']
  pouch_attr :body, encrypted_field: :secret_stuff,
    migrate_from_field: :please_no_snooping
end
```

It's safe to use the same name as the name of the encrypted attribute.


#### Key rotation

Because AttrVault uses a keyring, with access to multiple keys at
once, key rotation is fairly straightforward: if you add a key to the
keyring with a more recent `created_at` than any other key, that key
will automatically be used for encryption. Any keys that are no longer
in use can be removed from the keyring.

To check if an existing key with id 123 is still in use, run:

```ruby
DiaryEntry.where(key_id: 123).empty?
```

If this is true, the key with that id can be safely removed.

For a large dataset, you may want to index the `key_id` column.


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
