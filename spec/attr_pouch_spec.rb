require 'spec_helper'

describe AttrPouch do
  context "with a string attribute" do
    let(:bepouched) do
      Class.new(Sequel::Model(:items)) do
        include AttrPouch

        pouch(:attrs) do
          field :foo, String
        end
      end
    end
    let(:pouchy) { bepouched.create }

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
  end

  context "with an attribute that is not a simple method name" do
    it "raises an error when defining the class" do
      expect do
        Class.new(Sequel::Model(:items)) do
          include AttrPouch

          pouch(:attrs) do
            field :"nope, not valid",  String
          end
        end
      end.to raise_error(AttrPouch::InvalidFieldError)
    end
  end

  context "with an attribute that ends in a question mark" do
    let(:bepouched) do
      Class.new(Sequel::Model(:items)) do
        include AttrPouch

        pouch(:attrs) do
          field :foo?, :bool
        end
      end
    end
    let(:pouchy) { bepouched.create }

    it "generates normal getter" do
      expect(pouchy.foo?).to be_nil
    end

    it "generates setter by stripping trailing question mark" do
      pouchy.foo = true
      expect(pouchy.foo?).to be true
    end
  end
end
