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

    def self.encode(type, &block)
      @@encoders ||= {}
      @@encoders[type] = block
    end

    def self.decode(type, &block)
      @@decoders ||= {}
      @@decoders[type] = block
    end

    def self.encoders; @@encoders; end
    def self.decoders; @@decoders; end

    def self.infer_type(field=nil, &block)
      if block_given?
        @@type_inferrer = block
      else
        if @@type_inferrer.nil?
          raise InvalidFieldError, "No type inference configured"
        else
          type = @@type_inferrer.call(field)
          if type.nil?
            raise InvalidFieldError, "Could not infer type of field #{field}"
          end
          type
        end
      end
    end

    def initialize(name, type, opts)
      @name = name
      if type.nil?
        @type = self.class.infer_type(self)
      else
        @type = to_class(type)
      end
      @raw_type = type
      @opts = opts
    end

    def alias_as(new_name)
      if new_name == name
        self
      else
        self.class.new(new_name, type, opts)
      end
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

    def mutable?
      opts.fetch(:mutable, true)
    end

    def deletable?
      opts.fetch(:deletable, false)
    end

    def previous_aliases
      was = opts.fetch(:was, [])
      if was.respond_to?(:to_a)
        was.to_a
      else
        [ was ]
      end
    end

    def all_names
      [ name ] + previous_aliases
    end

    def write(store, value, encode: true)
      if store.has_key?(name)
        raise ImmutableFieldUpdateError unless mutable?
      end
      if encode
        value = self.encode(value)
      end
      if !store.has_key?(name) || value != store[name]
        store[name] = value
        previous_aliases.each { |a| store.delete(a) }
        true
      else
        false
      end
    end

    def read(store, decode: true)
      present_as = all_names.find { |n| !store.nil? && store.has_key?(n) }
      if store.nil? || present_as.nil?
        if required?
          raise MissingRequiredFieldError,
                "Expected field #{inspect} to exist"
        else
          default if decode
        end
      elsif present_as == name
        raw = store.fetch(name)
        if decode
          decode(raw)
        else
          raw
        end
      else
        alias_as(present_as).read(store)
      end
    end

    def decode(value)
      decoder.call(self, value) unless value.nil?
    end

    def encode(value)
      encoder.call(self, value) unless value.nil?
    end

    def decoder
      @decoder ||= self.class.decoders
                 .find(method(:ensure_decoder)) do |decoder_type, _|
        compatible_codec?(decoder_type)
      end.last
    end

    def encoder
      @encoder ||= self.class.encoders
                 .find(method(:ensure_encoder)) do |encoder_type, _|
        compatible_codec?(encoder_type)
      end.last
    end

    private

    def compatible_codec?(codec_type)
      if self.type.is_a?(Class) && codec_type.is_a?(Class)
        self.type <= codec_type
      else
        self.type == codec_type
      end
    rescue
      false
    end

    def ensure_encoder
      raise MissingCodecError,
            "No encoder found for #{inspect}"
    end

    def ensure_decoder
      raise MissingCodecError,
            "No decoder found for #{inspect}"
    end

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
    end

    def infer_type(&block)
      if block_given?
        Field.infer_type(&block)
      else
        raise ArgumentError, "Expected block to infer types with"
      end
    end

    def encode(type, &block)
      Field.encode(type, &block)
    end

    def decode(type, &block)
      Field.decode(type, &block)
    end
  end

  class Pouch
    VALID_FIELD_NAME_REGEXP = %r{\A[a-zA-Z0-9_]+\??\z}

    def initialize(host, storage_field, default_pouch: Sequel.hstore({}))
      @host = host
      @storage_field = storage_field
      @default_pouch = default_pouch
      @fields = {}
    end

    def field_definition(name)
      @fields[name]
    end

    def field(name, type, opts={})
      unless VALID_FIELD_NAME_REGEXP.match(name)
        raise InvalidFieldError, "Field name must match #{VALID_FIELD_NAME_REGEXP}"
      end

      field = Field.new(name, type, opts)
      @fields[name] = field

      storage_field = @storage_field
      default = @default_pouch

      @host.class_eval do
        def_dataset_method(:where_pouch) do |pouch_field, expr_hash|
          # TODO: encode the values so we can query properly
          ds = self
          expr_hash.each do |key, value|
            pouch = model.pouch(pouch_field)
            if pouch.nil?
              raise ArgumentError,
                    "No pouch defined for #{pouch_field}"
            end
            field = pouch.field_definition(key)
            if field.nil?
              raise ArgumentError,
                    "No field #{key} defined for pouch #{pouch_field}"
            end

            if value.respond_to?(:each)
              value.each_with_index do |v,i|
                encoded_val = field.encode(v)
                if i == 0
                  ds = ds.where(Sequel.hstore(pouch_field)
                                 .contains(Sequel.hstore(key => encoded_val)))
                else
                  ds = ds.or(Sequel.hstore(pouch_field)
                              .contains(Sequel.hstore(key => encoded_val)))
                end
              end
            elsif value.nil?
              ds = ds.where(Sequel.hstore(pouch_field).has_key?(key.to_s) => false)
                   .or(Sequel.hstore(pouch_field)
                        .contains(Sequel.hstore(key => nil)))
            else
              ds = ds.where(Sequel.hstore(pouch_field)
                             .contains(Sequel.hstore(key => field.encode(value))))
            end
          end
          ds
        end

        define_method(name) do
          store = self[storage_field]
          field.read(store)
        end

        define_method("#{name.to_s.sub(/\?\z/, '')}=") do |value|
          store = self[storage_field]
          was_nil = store.nil?
          store = default if was_nil
          changed = field.write(store, value)
          if was_nil
            self[storage_field] = store
          else
            modified! storage_field if changed
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
            field.read(store, decode: false)
          end

          define_method("#{raw_name.to_s.sub(/\?\z/, '')}=") do |value|
            store = self[storage_field]
            was_nil = store.nil?
            store = default if was_nil
            changed = field.write(store, value, encode: false)
            if was_nil
              self[storage_field] = store
            else
              modified! storage_field if changed
            end
          end
        end
      end
    end
  end

  module ClassMethods
    def pouch(field, &block)
      if block_given?
        pouch = Pouch.new(self, field)
        @pouches ||= {}
        @pouches[field] = pouch
        pouch.instance_eval(&block)
      else
        @pouches[field]
      end
    end
  end
end

AttrPouch.configure do |config|
  config.encode(String) do |field, value|
    value.to_s
  end
  config.decode(String) do |field, value|
    value
  end

  config.encode(Integer) do |field, value|
    value.to_s
  end
  config.decode(Integer) do |field, value|
    Integer(value)
  end
  
  config.encode(Float) do |field, value|
    value.to_s
  end
  config.decode(Float) do |field, value|
    Float(value)
  end

  config.encode(Time) do |field, value|
    value.strftime('%Y-%m-%d %H:%M:%S.%N')
  end
  config.decode(Time) do |field, value|
    Time.parse(value)
  end

  config.encode(:bool) do |field, value|
    value.to_s
  end
  config.decode(:bool) do |field, value|
    value == 'true'
  end

  config.encode(Sequel::Model) do |field, value|
    klass = field.type
    value[klass.primary_key]
  end
  config.decode(Sequel::Model) do |field, value|
    klass = field.type
    klass[value]
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
