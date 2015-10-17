require 'pg'
require 'sequel'
require 'attr_pouch/errors'

module AttrPouch
  def self.configure
    @@config ||= Config.new
    yield @@config
  end

  def self.config
    @@config ||= Config.new
  end

  def self.included(base)
    base.extend(ClassMethods)
  end

  class Field
    attr_reader :name, :type, :raw_type, :opts

    def initialize(name, type, opts)
      @name = name
      @type = to_class(type)
      @raw_type = type
      @opts = opts
    end

    def alias_as(new_name)
      self.class.new(new_name, type, opts)
    end

    def required?
      !(has_default? || deletable?)
    end

    def has_default?
      opts.has_key?(:default)
    end

    def default
      opts.fetch(:default, nil)
    end

    def immutable?
      opts.fetch(:immutable, false)
    end

    def deletable?
      opts.fetch(:deletable, false)
    end

    def previous_aliases
      was = opts.fetch(:was, [])
      was.is_a?(Array) ? was : [ was ]
    end

    def all_names
      [ name ] + previous_aliases
    end

    private

    def to_class(type)
      return type if type.is_a?(Class) || type.is_a?(Symbol)
      type.to_s.split('::').inject(Object) do |moodule, klass|
        moodule.const_get(klass)
      end
    end
  end

  class Config
    def initialize
      @encoders = {}
      @decoders = {}
      @type_inferrer = nil
    end

    def infer_type(field=nil, &block)
      if block_given?
        @type_inferrer = block
        return
      end
      if @type_inferrer.nil?
        raise InvalidFieldError, "Could not infer type of field #{field.inspect}"
      else
        type = @type_inferrer.call(field)
        if type.nil?
          raise InvalidFieldError, "Could not infer type of field #{field.inspect}"
        end
        type
      end
    end

    def write(type, &block)
      @encoders[type] = block
    end

    def read(type, &block)
      @decoders[type] = block
    end

    def find_encoder(field)
      encoder = @encoders.find(->{[]}) do |type, _|
        field.type <= type rescue false
      end.last
      if encoder.nil?
        raise MissingCodecError, "No encoder found for field #{field.inspect}"
      end
      encoder
    end

    def find_decoder(field)
      decoder = @decoders.find(->{[]}) do |type, _|
        field.type <= type rescue false
      end.last 
      if decoder.nil?
        raise MissingCodecError, "No decoder found for field #{field.inspect}"
      end
      decoder
    end
  end

  class Pouch
    VALID_FIELD_NAME_REGEXP = %r{\A[a-zA-Z0-9_]+\??\z}

    def initialize(host, storage_field, default_pouch: Sequel.hstore({}))
      @host = host
      @storage_field = storage_field
      @default_pouch = default_pouch
    end

    def field(name, type, opts={})
      unless VALID_FIELD_NAME_REGEXP.match(name)
        raise InvalidFieldError, "Field name must match #{VALID_FIELD_NAME_REGEXP}"
      end

      field = Field.new(name, type, opts)
      if type.nil?
        type = AttrPouch.config.infer_type(field)
        field = Field.new(name, type, opts)
      end

      decoder = AttrPouch.config.find_decoder(field)
      encoder = AttrPouch.config.find_encoder(field)
      storage_field = @storage_field
      default = @default_pouch

      @host.class_eval do
        define_method(name) do
          store = self[storage_field]
          present_as = field.all_names.find { |n| store.has_key?(n) }
          if store.nil? || present_as.nil?
            if field.required?
              raise MissingRequiredFieldError,
                    "Expected field #{field.inspect} to exist"
            else
              field.default
            end
          else
            decoder.call(field.alias_as(present_as), store)
          end
        end

        define_method("#{name.to_s.sub(/\?\z/, '')}=") do |value|
          store = self[storage_field]
          was_nil = store.nil?
          store = default if was_nil
          if store.has_key?(field.name)
            raise ImmutableFieldUpdateError if field.immutable?
          end
          encoder.call(field, store, value)
          field.previous_aliases.each { |a| store.delete(a) }
          if was_nil
            self[storage_field] = store
          else
            modified! storage_field
          end
        end

        if field.deletable?
          delete_method = "delete_#{name.to_s.sub(/\?\z/, '')}"
          define_method(delete_method) do
            store = self[storage_field]
            unless store.nil?
              field.all_names.each { |a| store.delete(a) }
              modified! storage_field
            end
          end

          define_method("#{delete_method}!") do
            self.public_send(delete_method)
            save_changes
          end
        end

        if opts.has_key?(:raw_field)
          raw_name = opts[:raw_field]

          define_method(raw_name) do
            store = self[storage_field]
            present_as = field.all_names.find { |n| store.has_key?(n) }
            if store.nil? || present_as.nil?
              if field.required?
                raise MissingRequiredFieldError,
                      "Expected field #{field.inspect} to exist"
              end
            else
              store[present_as]
            end
          end

          define_method("#{raw_name.to_s.sub(/\?\z/, '')}=") do |value|
            store = self[storage_field]
            was_nil = store.nil?
            store = default if was_nil
            if store.has_key?(field.name)
              raise ImmutableFieldUpdateError if field.immutable?
            end
            store[name] = value
            field.previous_aliases.each { |a| store.delete(a) }

            if was_nil
              self[storage_field] = store
            else
              modified! storage_field
            end
          end
        end
      end
    end
  end

  module ClassMethods
    def pouch(field, &block)
      pouch = Pouch.new(self, field)
      pouch.instance_eval(&block)
    end
    # Add a dataset_method `where_pouch_field(pouch, expr_hash)` that
    # behaves like `where` does for normal fields. A start is
    #
    #   where(Sequel.hstore_op(pouch.field).contains(expr_hash)))
    #
    # but this doesn't behave how one might expect with
    #  - arrays: the array is serialized to a single hstore element
    #     (unlike the automatic IN translation for native attributes)
    #  - nil: the hstore column is checked for the existence of a key
    #    pointing to a null value: the absence of a key is not considered
    #    equivalent
  end
end

AttrPouch.configure do |config|
  config.write(String) do |field, store, value|
    store[field.name] = value.to_s
  end
  config.read(String) do |field, store|
    store[field.name]
  end

  config.write(Integer) do |field, store, value|
    store[field.name] = value
  end
  config.read(Integer) do |field, store|
    Integer(store[field.name])
  end
  
  config.write(Float) do |field, store, value|
    store[field.name] = value
  end
  config.read(Float) do |field, store|
    Float(store[field.name])
  end

  config.write(Time) do |field, store, value|
    store[field.name] = value.strftime('%Y-%m-%d %H:%M:%S.%N')
  end
  config.read(Time) do |field, store|
    Time.parse(store[field.name])
  end

  config.write(:bool) do |field, store, value|
    store[field.name] = value.to_s
  end
  config.read(:bool) do |field, store, value|
    store[field.name] == 'true'
  end

  config.write(Sequel::Model) do |field, store, value|
    klass = field.type
    store[field.name] = value[klass.primary_key]
  end
  config.read(Sequel::Model) do |field, store|
    klass = field.type
    klass[store[field.name]]
  end

  config.infer_type do |field|
    case field.name
    when /\Anum_|_(?:count|size)\z/
      Integer
    when /_(?:at|by)\z/
      Time
    when /\?\z/
      :bool
    else
      String
    end
  end
end
