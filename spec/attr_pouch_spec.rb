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
      expect(pouchy.foo).to be_nil
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
      expect(pouchy.foo?).to be_nil
    end

    it "generates setter by stripping trailing question mark" do
      pouchy.foo = true
      expect(pouchy.foo?).to be true
    end
  end
end
