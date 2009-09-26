# encoding: UTF-8

# This file provides Ruby 1.8 compatibility. The intended functionality
# is not present, because we cannot guess the original encoding, thus
# making Iconv unsuitable for a conversion.
if RUBY_VERSION < "1.9"
  class String
    def force_encoding(encoding)
      self
    end
  end
end
