module AttrPouch
  # Base class for AttrPouch errors
  class Error < StandardError; end
  class MissingCodecError < Error; end
  class InvalidFieldError < Error; end
end
