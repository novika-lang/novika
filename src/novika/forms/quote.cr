module Novika
  # Represents Novika quotes, which are known as strings in
  # most other programming languages.
  struct Quote
    include Form
    extend HasDesc

    # Returns the underlying string value.
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

    def desc(io : IO)
      io << "quote (aka string in other languages) with value: "
      string.dump_unquoted(io)
    end

    def self.desc(io : IO)
      io << "a quote"
    end

    # Concatenates two quotes, and returns the resulting quote.
    def +(other : Quote) : Quote
      Quote.new(string + other.string)
    end

    def enquote(engine : Engine) : Quote
      self
    end

    def to_s(io)
      io << "'"; string.dump_unquoted(io); io << "'"
    end

    def_equals_and_hash string
  end
end
