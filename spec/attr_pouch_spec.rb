require 'spec_helper'

describe AttrPouch do
  %i[hstore json jsonb].each do |storage_kind|

    context "with a #{storage_kind} backing column" do

      let(:column_name) { "attrs_#{storage_kind}".to_sym }
      let(:storage_wrapper) do
        case storage_kind
        when :hstore
          ->(hash) { Sequel.hstore(hash) }
        when :json, :jsonb
          ->(hash) { Sequel.pg_json(hash) }
        else
          raise ArgumentError, "Unknown kind, #{kind}"
        end
      end

      def make_pouchy(field_name, opts={})
        col_name = column_name
        Class.new(Sequel::Model(:items)) do
          include AttrPouch

          pouch(col_name) do
            field field_name, opts
          end
        end.create
      end

      def wrap_hash(hash)
        hash = Hash[hash.map { |k,v| [ k.to_s, v ] }]
        storage_wrapper.call(hash)
      end

      context "with a simple attribute" do
        let(:pouchy) { make_pouchy(:foo, type: String) }

        it "generates getter and setter" do
          pouchy.foo = 'bar'
          expect(pouchy.foo).to eq('bar')
        end

        it "clears on reload" do
          pouchy.update(foo: 'bar')
          expect(pouchy.foo).to eq('bar')
          pouchy.foo = 'baz'
          pouchy.reload
          expect(pouchy.foo).to eq('bar')
        end

        it "marks the field as modified" do
          pouchy.foo = 'bar'
          result = pouchy.save_changes
          expect(result).to_not be_nil
          pouchy.reload
          expect(pouchy.foo).to eq('bar')
        end

        it "avoids marking the field as modified if it is not changing" do
          pouchy.foo = 'bar'
          expect(pouchy.save_changes).to_not be_nil
          pouchy.foo = 'bar'
          expect(pouchy.save_changes).to be_nil
        end

        it "requires the attribute to be present if read" do
          expect { pouchy.foo }.to raise_error(AttrPouch::MissingRequiredFieldError)
        end

        context "with nil values" do
          let(:pouchy) { make_pouchy(:f1, type: :nil_hater) }

          before do
            AttrPouch.configure do |config|
              config.encode(:nil_hater) { |f,v| v.nil? ? (raise ArgumentError) : v }
              config.decode(:nil_hater) { |f,v| v.nil? ? (raise ArgumentError) : v }
            end
          end

          it "bypasses encoding" do
            pouchy.update(f1: 'foo')
            expect { pouchy.update(f1: nil) }.not_to raise_error
            expect(pouchy.f1).to be_nil
          end

          it "bypasses decoding" do
            pouchy.update(column_name => wrap_hash(f1: nil))
            expect { pouchy.f1 }.not_to raise_error
            expect(pouchy.f1).to be_nil
          end

          it "still records the value as nil if not present when writing" do
            pouchy.update(f1: nil)
            expect(pouchy[column_name]).to have_key('f1')
            expect(pouchy[column_name].fetch('f1')).to be_nil
          end
        end
      end

      context "with an integer attribute" do
        let(:pouchy) { make_pouchy(:foo, type: Integer) }

        it "preserves the type" do
          pouchy.update(foo: 42)
          pouchy.reload
          expect(pouchy.foo).to eq(42)
        end
      end

      context "with a float attribute" do
        let(:pouchy) { make_pouchy(:foo, type: Float) }

        it "preserves the type" do
          pouchy.update(foo: 2.78)
          pouchy.reload
          expect(pouchy.foo).to eq(2.78)
        end
      end

      context "with a boolean attribute" do
        let(:pouchy) { make_pouchy(:foo, type: :bool) }

        it "preserves the type" do
          pouchy.update(foo: true)
          pouchy.reload
          expect(pouchy.foo).to be true
        end
      end

      context "with a Time attribute" do
        let(:pouchy) { make_pouchy(:foo, type: Time) }

        it "preserves the type" do
          now = Time.now
          pouchy.update(foo: now)
          pouchy.reload
          expect(pouchy.foo).to eq(now)
        end
      end

      context "with a Sequel::Model attribute" do
        let(:model_class) { Class.new(Sequel::Model(:items)) }
        let(:pouchy)      { make_pouchy(:foo, type: model_class) }

        it "preserves the type" do
          new_model = model_class.create
          pouchy.update(foo: new_model)
          pouchy.reload
          expect(pouchy.foo).to be_a(model_class)
          expect(pouchy.foo.id).to eq(new_model.id)
        end
      end

      context "with a Sequel::Model attribute provided as a String" do
        let(:model_class) do
          module A; class B < Sequel::Model(:items); end; end; A::B
        end
        let(:pouchy) { make_pouchy(:foo, type: model_class.name) }

        it "preserves the type" do
          new_model = model_class.create
          pouchy.update(foo: new_model)
          pouchy.reload
          expect(pouchy.foo).to be_a(model_class)
          expect(pouchy.foo.id).to eq(new_model.id)
        end
      end

      context "with an attribute that is not a simple method name" do
        it "raises an error when defining the class" do
          expect do
            make_pouchy(:"nope, not valid", type: String)
          end.to raise_error(AttrPouch::InvalidFieldError)
        end
      end

      context "with an attribute name that ends in a question mark" do
        let(:pouchy) { make_pouchy(:foo?, type: :bool) }

        it "generates normal getter" do
          pouchy[column_name] = wrap_hash(foo?: true)
          expect(pouchy.foo?).to be true
        end

        it "generates setter by stripping trailing question mark" do
          pouchy.foo = true
          expect(pouchy.foo?).to be true
        end
      end

      context "with multiple attributes" do
        let(:bepouched) do
          col_name = column_name

          Class.new(Sequel::Model(:items)) do
            include AttrPouch

            pouch(col_name) do
              field :f1, type: String
              field :f2, type: :bool
              field :f3, type: Integer
            end
          end
        end
        let(:pouchy) { bepouched.create }

        it "allows updating multiple attributes simultaneously" do
          pouchy.update(f1: 'hello', f2: true, f3: 42)
          expect(pouchy.f1).to eq('hello')
          expect(pouchy.f2).to eq(true)
          expect(pouchy.f3).to eq(42)
        end

        it "allows updating multiple attributes sequentially" do
          pouchy.f1 = 'hello'
          pouchy.f2 = true
          pouchy.f3 = 42
          pouchy.save_changes
          pouchy.reload
          expect(pouchy.f1).to eq('hello')
          expect(pouchy.f2).to eq(true)
          expect(pouchy.f3).to eq(42)
        end
      end

      context "with the default option" do
        let(:pouchy) { make_pouchy(:foo, type: String, default: 'hello') }

        it "returns the default if the key is absent" do
          expect(pouchy.foo).to eq('hello')
        end

        it "returns the value if the key is present" do
          pouchy.update(foo: 'goodbye')
          expect(pouchy.foo).to eq('goodbye')
        end

        context "with the deletable option" do
          let(:pouchy) { make_pouchy(:foo, type: String,
                                     default: 'hello',
                                     deletable: true) }

          it "it returns the default if the key is absent" do
            expect(pouchy.foo).to eq('hello')
          end

          it "it returns the default after the field has been deleted" do
            pouchy.update(foo: 'goodbye')
            expect(pouchy.foo).to eq('goodbye')
            pouchy.delete_foo
            expect(pouchy.foo).to eq('hello')
          end
        end
      end

      context "with the deletable option" do
        let(:pouchy) { make_pouchy(:foo, type: Integer, deletable: true) }

        it "is nil if the field is absent" do
          expect(pouchy.foo).to be_nil
        end

        it "supports deleting existing fields" do
          pouchy.update(foo: 42)
          expect(pouchy.foo).to eq(42)
          pouchy.delete_foo
          expect(pouchy[column_name]).not_to have_key(:foo)
          pouchy.reload
          expect(pouchy.foo).to eq(42)
        end

        it "supports deleting existing fields and immediately persisting changes" do
          pouchy.update(foo: 42)
          expect(pouchy.foo).to eq(42)
          pouchy.delete_foo!
          expect(pouchy[column_name]).not_to have_key(:foo)
          pouchy.reload
          expect(pouchy[column_name]).not_to have_key(:foo)
        end

        it "ignores deleting absent fields" do
          expect(pouchy[column_name]).not_to have_key(:foo)
          pouchy.delete_foo
          expect(pouchy[column_name]).not_to have_key(:foo)
        end

        it "also deletes aliases from the was option" do
          pouchy = make_pouchy(:foo, type: Integer, deletable: true, was: :bar)

          pouchy.update(column_name => wrap_hash(bar: 42))
          expect(pouchy.foo).to eq(42)
          pouchy.delete_foo
          expect(pouchy[column_name]).not_to have_key(:bar)
        end
      end

      context "with the mutable option" do
        let(:pouchy) { make_pouchy(:foo, type: Integer, mutable: false) }

        it "it allows setting the field value for the first time" do
          pouchy.update(foo: 42)
        end

        it "forbids subsequent modifications to the field" do
          pouchy.update(foo: 42)
          expect do
            pouchy.update(foo: 43)
          end.to raise_error(AttrPouch::ImmutableFieldUpdateError)
        end
      end

      context "with the was option" do
        let(:pouchy) { make_pouchy(:foo, type: String, was: %w(bar baz)) }

        it "supports aliases for renaming fields" do
          pouchy.update(column_name => wrap_hash(bar: 'hello'))
          expect(pouchy.foo).to eq('hello')
        end

        it "supports multiple aliases" do
          pouchy.update(column_name => wrap_hash(baz: 'hello'))
          expect(pouchy.foo).to eq('hello')
        end

        it "deletes old names when writing the current one" do
          pouchy.update(column_name => wrap_hash(bar: 'hello'))
          pouchy.update(foo: 'goodbye')
          expect(pouchy[column_name]).not_to have_key(:bar)
        end

        it "supports a shorthand for the single-alias case" do
          pouchy = make_pouchy(:foo, type: String, was: :bar)
          pouchy.update(column_name => wrap_hash(bar: 'hello'))
          expect(pouchy.foo).to eq('hello')
        end
      end

      context "with the raw_field option" do
        let(:pouchy) { make_pouchy(:foo, type: Float, raw_field: :raw_foo) }

        it "supports direct access to the encoded value" do
          pouchy.update(foo: 2.78)
          expect(pouchy.raw_foo).to eq('2.78')
        end

        it "is required when read" do
          expect do
            pouchy.raw_foo
          end.to raise_error(AttrPouch::MissingRequiredFieldError)
        end

        it "avoids marking the field as modified if it is not changing" do
          pouchy.raw_foo = 'bar'
          expect(pouchy.save_changes).to_not be_nil
          pouchy.raw_foo = 'bar'
          expect(pouchy.save_changes).to be_nil
        end

        it "obeys the 'mutable' option" do
          pouchy = make_pouchy(:foo, type: Float,
                               raw_field: :raw_foo,
                               mutable: false)
          pouchy.update(foo: 42)
          expect do
            pouchy.update(foo: 43)
          end.to raise_error(AttrPouch::ImmutableFieldUpdateError)
        end

        it "is nil when the 'default' option is present" do
          pouchy = make_pouchy(:foo, type: Float, raw_field: :raw_foo, default: 7.2)
          expect(pouchy.raw_foo).to be_nil
        end

        it "obeys the 'was' option when reading" do
          pouchy = make_pouchy(:foo, type: String, raw_field: :raw_foo, was: :bar)
          pouchy[column_name] = wrap_hash(bar: 'hello')
          expect(pouchy.raw_foo).to eq('hello')
        end

        it "obeys the 'was' option when writing" do
          pouchy = make_pouchy(:foo, type: String, raw_field: :raw_foo, was: :bar)
          pouchy[column_name] = wrap_hash(bar: 'hello')
          pouchy.update(raw_foo: 'goodbye')
          expect(pouchy[column_name]).not_to have_key(:bar)
        end
      end

      context "inferring field types" do
        it "infers field named num_foo to be of type Integer" do
          pouchy = make_pouchy(:num_foo)
          pouchy.update(num_foo: 42)
          expect(pouchy.num_foo).to eq(42)
        end

        it "infers field named foo_count to be of type Integer" do
          pouchy = make_pouchy(:foo_count)
          pouchy.update(foo_count: 42)
          expect(pouchy.foo_count).to eq(42)
        end

        it "infers field named foo_size to be of type Integer" do
          pouchy = make_pouchy(:foo_size)
          pouchy.update(foo_size: 42)
          expect(pouchy.foo_size).to eq(42)
        end

        it "infers field named foo? to be of type :bool" do
          pouchy = make_pouchy(:foo?)
          pouchy.update(foo: true)
          expect(pouchy.foo?).to be true
        end

        it "infers field named foo_at to be of type Time" do
          now = Time.now
          pouchy = make_pouchy(:foo_at)
          pouchy.update(foo_at: now)
          expect(pouchy.foo_at).to eq(now)
        end

        it "infers field named foo_by to be of type Time" do
          now = Time.now
          pouchy = make_pouchy(:foo_by)
          pouchy.update(foo_by: now)
          expect(pouchy.foo_by).to eq(now)
        end

        it "infers field named foo to be of type String" do
          pouchy = make_pouchy(:foo)
          pouchy.update(foo: 'hello')
          expect(pouchy.foo).to eq('hello')
        end
      end

      context "with dataset methods" do
        let(:bepouched) do
          col_name = column_name

          Class.new(Sequel::Model(:items)) do
            include AttrPouch

            pouch(col_name) do
              field :f1, type: String
              field :f2, type: String
              field :f3, type: String
              field :f4, type: :rot13
            end
          end
        end

        def rot13(str)
          str.each_byte.map do |c|
            case c
            when 'a'.ord..('z'.ord - 13)
              c + 13
            when ('z'.ord - 13)..'z'.ord
              c - 13
            end
          end.map(&:chr).join
        end

        before do
          AttrPouch.configure do |config|
            config.encode(:rot13) { |f,v| rot13(v.to_s) }
            config.decode(:rot13) { |f,v| rot13(v) }
          end
        end

        if storage_kind == :json
          it "does not support dataset methods" do
            pouchy = bepouched.create(f1: 'foo', f2: 'bar', f3: 'baz')
            bepouched.create(f1: 'bar', f2: 'foo', f3: 'baz') # *not* matching
            expect do
              bepouched.where_pouch(column_name, f1: 'foo').all
            end.to raise_error(::AttrPouch::UnsupportedError)
          end
        else
          it "finds the right item with a scalar field value" do
            pouchy = bepouched.create(f1: 'foo', f2: 'bar', f3: 'baz')
            bepouched.create(f1: 'bar', f2: 'foo', f3: 'baz') # *not* matching
            matching = bepouched.where_pouch(column_name, f1: 'foo').all
            expect(matching.count).to eq(1)
            match = matching.first
            expect(match.id).to eq(pouchy.id)
          end

          it "finds the right item with an array field value" do
            p1 = bepouched.create(f1: 'foo', f2: 'bar', f3: 'baz')
            p2 = bepouched.create(f1: 'bar', f2: 'foo', f3: 'baz')
            bepouched.create(f1: 'baz', f2: 'foo', f3: 'bar') # *not* matching
            matching = bepouched.where_pouch(column_name, f1: %w(foo bar)).all
            expect(matching.count).to eq(2)
            expect(matching.map(&:id)).to include(p1.id, p2.id)
          end

          it "finds the right item with a missing field value" do
            p1 = bepouched.create(f2: 'bar', f3: 'baz')
            bepouched.create(f1: '', f2: 'foo', f3: 'baz') # *not* matching
            bepouched.create(f1: 'baz', f2: 'foo', f3: 'bar') # *not* matching
            matching = bepouched.where_pouch(column_name, f1: nil).all
            expect(matching.count).to eq(1)
            expect(matching.first.id).to eq(p1.id)
          end

          it "finds the right item with a nil field value" do
            p1 = bepouched.create(column_name => wrap_hash(f1: nil))
            matching = bepouched.where_pouch(column_name, f1: nil).all
            expect(matching.count).to eq(1)
            expect(matching.first.id).to eq(p1.id)
          end

          it "uses the associated encoder for lookups" do
            encoded = rot13('hello')
            p1 = bepouched.create(f4: 'hello')
            expect(p1[column_name]['f4']).to eq(encoded) # nothing behind the curtain
            matching = bepouched.where_pouch(column_name, f4: 'hello')
            expect(matching.count).to eq(1)
            expect(matching.first.id).to eq(p1.id)
          end

          context "using indexes" do
            before do
              bepouched.create(column_name => wrap_hash(f1: nil))
            end

            def plan_when_looking_for(values)
              stmt = bepouched.where_pouch(column_name, f1: values).sql
              db = bepouched.db
              db.transaction do
                db.run("SET LOCAL enable_seqscan = false")
                db.fetch("EXPLAIN #{stmt}").all
              end.map { |line| line.fetch(:"QUERY PLAN") }.join("\n")
            end

            it "uses index when looking for a single value" do
              expect(plan_when_looking_for('hello')).to match(/index/i)
            end

            it "uses index when looking for multiple values" do
              expect(plan_when_looking_for(%(hello world))).to match(/index/i)
            end

            xit "uses index when looking for a nil value" do
              expect(plan_when_looking_for(nil)).to match(/index/i)
            end
          end
        end
      end
    end
  end
end
