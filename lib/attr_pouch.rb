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
      @default_pouch = default_pouch
      @storage_field = storage_field
    end

    def field(name, type, opts={})
      unless VALID_FIELD_NAME_REGEXP.match(name)
        raise InvalidFieldError, "Field name must match #{VALID_FIELD_NAME_REGEXP}"
      end
      field = Field.new(name, type, opts)

      decoder = AttrPouch.config.find_decoder(field)
      encoder = AttrPouch.config.find_encoder(field)
      storage_field = @storage_field
      default = @default_pouch

      @host.class_eval do
        define_method(name) do
          store = self[storage_field]
          unless store.nil?
            decoder.call(field, store)
          end
        end

        define_method("#{name.to_s.sub(/\?\z/, '')}=") do |value|
          store = self[storage_field]
          was_nil = store.nil?
          store = default if was_nil
          encoder.call(field, store, value)
          if was_nil
            self[storage_field] = store
          else
            modified! storage_field
          end
        end

        if opts.has_key?(:raw_field)
          raw_name = opts[:raw_field]

          define_method(raw_name) do
            store = self[storage_field]
            unless store.nil?
              store[name]
            end
          end

          define_method("#{raw_name.to_s.sub(/\?\z/, '')}=") do |value|
            store = self[storage_field]
            was_nil = store.nil?
            store = default if was_nil
            store[name] = value
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
end
