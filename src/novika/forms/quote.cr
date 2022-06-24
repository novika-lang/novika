module Novika
  # Represents Novika quotes, which are known as strings in most
  # other programming languages.
  struct Quote
    include Form

    # Returns the underlying string.
    getter string : String

    # Initializes a quote from the given *string*.
    #
    # If *peel* is set to true, one slash will be removed before
    # every escape sequence in *string*: for example, `\\n` will
    # become `\n`, etc.
    def initialize(@string, peel = false)
      if peel
        @string = string
          .gsub("\\n", '\n')
          .gsub("\\t", '\t')
          .gsub("\\r", '\r')
          .gsub("\\v", '\v')
      end
    end

    def desc
      "quote (aka string in other languages) with value: '#{string.dump_unquoted}'"
    end

    # Concatenates two quotes, and returns the resulting quote.
    def +(other)
      Quote.new(string + other.string)
    end

    def enquote(world)
      self
    end

    def to_s(io)
      io << "'"; string.dump_unquoted(io); io << "'"
    end

    def_equals_and_hash string
  end
end
