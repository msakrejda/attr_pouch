module AttrPouch
  # Base class for AttrPouch errors
  class Error < StandardError; end
  class MissingCodecError < Error; end
  class InvalidFieldError < Error; end
  class InvalidPouchError < Error; end
  class MissingRequiredFieldError < Error; end
  class ImmutableFieldUpdateError < Error; end
  class UnsupportedError < Error; end
end
