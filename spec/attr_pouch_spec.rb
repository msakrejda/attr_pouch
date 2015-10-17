require 'spec_helper'

describe AttrPouch do
  def make_pouchy(field_name, field_type, opts={})
    bepouched = Class.new(Sequel::Model(:items)) do
      include AttrPouch

      pouch(:attrs) do
        field field_name, field_type, opts
      end
    end
    bepouched.create
  end

  context "with a string attribute" do
    let(:pouchy) { make_pouchy(:foo, String) }

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

    it "requires the attribute to be present if read" do
      expect { pouchy.foo }.to raise_error(AttrPouch::MissingRequiredFieldError)
    end
  end

  context "with an integer attribute" do
    let(:pouchy) { make_pouchy(:foo, Integer) }

    it "preserves the type" do
      pouchy.update(foo: 42)
      pouchy.reload
      expect(pouchy.foo).to eq(42)
    end
  end

  context "with a float attribute" do
    let(:pouchy) { make_pouchy(:foo, Float) }

    it "preserves the type" do
      pouchy.update(foo: 2.78)
      pouchy.reload
      expect(pouchy.foo).to eq(2.78)
    end
  end

  context "with a boolean attribute" do
    let(:pouchy) { make_pouchy(:foo, :bool) }

    it "preserves the type" do
      pouchy.update(foo: true)
      pouchy.reload
      expect(pouchy.foo).to be true
    end
  end

  context "with a Time attribute" do
    let(:pouchy) { make_pouchy(:foo, Time) }

    it "preserves the type" do
      now = Time.now
      pouchy.update(foo: now)
      pouchy.reload
      expect(pouchy.foo).to eq(now)
    end
  end

  context "with a Sequel::Model attribute" do
    let(:model_class) { Class.new(Sequel::Model(:items)) }
    let(:pouchy)      { make_pouchy(:foo, model_class) }

    it "preserves the type" do
      new_model = model_class.create
      pouchy.update(foo: new_model)
      pouchy.reload
      expect(pouchy.foo).to be_a(model_class)
      expect(pouchy.foo.id).to eq(new_model.id)
    end
  end

  context "with a Sequel::Model attribute provided as a String" do
    let(:model_class) { module A; class B < Sequel::Model(:items); end; end; A::B }
    let(:pouchy)      { make_pouchy(:foo, model_class.name) }

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
        make_pouchy(:"nope, not valid", String)
      end.to raise_error(AttrPouch::InvalidFieldError)
    end
  end

  context "with an attribute name that ends in a question mark" do
    let(:pouchy) { make_pouchy(:foo?, :bool) }

    it "generates normal getter" do
      pouchy.attrs = Sequel.hstore(foo?: true)
      expect(pouchy.foo?).to be true
    end

    it "generates setter by stripping trailing question mark" do
      pouchy.foo = true
      expect(pouchy.foo?).to be true
    end
  end

  context "with multiple attributes" do
    let(:bepouched) do
      Class.new(Sequel::Model(:items)) do
        include AttrPouch

        pouch(:attrs) do
          field :f1, String
          field :f2, :bool
          field :f3, Integer
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
    let(:pouchy) { make_pouchy(:foo, String, default: 'hello') }

    it "returns the default if the key is absent" do
      expect(pouchy.foo).to eq('hello')
    end

    it "returns the value if the key is present" do
      pouchy.update(foo: 'goodbye')
      expect(pouchy.foo).to eq('goodbye')
    end

    context "with the deletable option" do
      let(:pouchy) { make_pouchy(:foo, String, default: 'hello', deletable: true) }

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
    let(:pouchy) { make_pouchy(:foo, Integer, deletable: true) }

    it "is nil if the field is absent" do
      expect(pouchy.foo).to be_nil
    end

    it "supports deleting existing fields" do
      pouchy.update(foo: 42)
      expect(pouchy.foo).to eq(42)
      pouchy.delete_foo
      expect(pouchy.attrs).not_to have_key(:foo)
      pouchy.reload
      expect(pouchy.foo).to eq(42)
    end

    it "supports deleting existing fields and immediately persisting changes" do
      pouchy.update(foo: 42)
      expect(pouchy.foo).to eq(42)
      pouchy.delete_foo!
      expect(pouchy.attrs).not_to have_key(:foo)
      pouchy.reload
      expect(pouchy.attrs).not_to have_key(:foo)
    end

    it "ignores deleting absent fields" do
      expect(pouchy.attrs).not_to have_key(:foo)
      pouchy.delete_foo
      expect(pouchy.attrs).not_to have_key(:foo)
    end

    it "also deletes aliases from the was option" do
      pouchy = make_pouchy(:foo, Integer, deletable: true, was: :bar)

      pouchy.update(attrs: Sequel.hstore(bar: 42))
      expect(pouchy.foo).to eq(42)
      pouchy.delete_foo
      expect(pouchy.attrs).not_to have_key(:bar)
    end
  end

  context "with the immutable option" do
    let(:pouchy) { make_pouchy(:foo, Integer, immutable: true) }

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
    let(:pouchy) { make_pouchy(:foo, String, was: %w(bar baz)) }

    it "supports aliases for renaming fields" do
      pouchy.update(attrs: Sequel.hstore(bar: 'hello'))
      expect(pouchy.foo).to eq('hello')
    end

    it "supports multiple aliases" do
      pouchy.update(attrs: Sequel.hstore(baz: 'hello'))
      expect(pouchy.foo).to eq('hello')
    end

    it "deletes old names when writing the current one" do
      pouchy.update(attrs: Sequel.hstore(bar: 'hello'))
      pouchy.update(foo: 'goodbye')
      expect(pouchy.attrs).not_to have_key(:bar)
    end

    it "supports a shorthand for the single-alias case" do
      pouchy = make_pouchy(:foo, String, was: :bar)
      pouchy.update(attrs: Sequel.hstore(bar: 'hello'))
      expect(pouchy.foo).to eq('hello')
    end
  end

  context "with the raw_field option" do
    let(:pouchy) { make_pouchy(:foo, Float, raw_field: :raw_foo) }

    it "supports direct access to the encoded value" do
      pouchy.update(foo: 2.78)
      expect(pouchy.raw_foo).to eq('2.78')
    end

    it "is required when read" do
      expect do
        pouchy.raw_foo
      end.to raise_error(AttrPouch::MissingRequiredFieldError)
    end

    it "obeys the 'immutable' option" do
      pouchy = make_pouchy(:foo, Float, raw_field: :raw_foo, immutable: true)
      pouchy.update(foo: 42)
      expect do
        pouchy.update(foo: 43)
      end.to raise_error(AttrPouch::ImmutableFieldUpdateError)
    end

    it "is nil when the 'default' option is present" do
      pouchy = make_pouchy(:foo, Float, raw_field: :raw_foo, default: 7.2)
      expect(pouchy.raw_foo).to be_nil
    end

    it "obeys the 'was' option when reading" do
      pouchy = make_pouchy(:foo, String, raw_field: :raw_foo, was: :bar)
      pouchy.attrs = Sequel.hstore(bar: 'hello')
      expect(pouchy.raw_foo).to eq('hello')
    end

    it "obeys the 'was' option when writing" do
      pouchy = make_pouchy(:foo, String, raw_field: :raw_foo, was: :bar)
      pouchy.attrs = Sequel.hstore(bar: 'hello')
      pouchy.update(raw_foo: 'goodbye')
      expect(pouchy.attrs).not_to have_key(:bar)
    end
  end

  context "inferring field types" do
    it "infers field named num_foo to be of type Integer" do
      pouchy = make_pouchy(:num_foo, nil)
      pouchy.update(num_foo: 42)
      expect(pouchy.num_foo).to eq(42)
    end

    it "infers field named foo_count to be of type Integer" do
      pouchy = make_pouchy(:foo_count, nil)
      pouchy.update(foo_count: 42)
      expect(pouchy.foo_count).to eq(42)
    end

    it "infers field named foo_size to be of type Integer" do
      pouchy = make_pouchy(:foo_size, nil)
      pouchy.update(foo_size: 42)
      expect(pouchy.foo_size).to eq(42)
    end

    it "infers field named foo? to be of type :bool" do
      pouchy = make_pouchy(:foo?, nil)
      pouchy.update(foo: true)
      expect(pouchy.foo?).to be true
    end

    it "infers field named foo_at to be of type Time" do
      now = Time.now
      pouchy = make_pouchy(:foo_at, nil)
      pouchy.update(foo_at: now)
      expect(pouchy.foo_at).to eq(now)
    end

    it "infers field named foo_by to be of type Time" do
      now = Time.now
      pouchy = make_pouchy(:foo_by, nil)
      pouchy.update(foo_by: now)
      expect(pouchy.foo_by).to eq(now)
    end

    it "infers field named foo to be of type String" do
      pouchy = make_pouchy(:foo, nil)
      pouchy.update(foo: 'hello')
      expect(pouchy.foo).to eq('hello')
    end
  end
end
