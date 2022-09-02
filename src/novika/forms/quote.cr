module Novika
  # Includers are Novika quotes, which are known as strings
  # in most other programming languages.
  #
  # Quotes are optimized for the ASCII-only case. Also, they
  # treat single `String::Grapheme`s separately from strings
  # of those, and cache grapheme counts here and there.
  #
  # The slowest operations on quotes are `slice_at` and `at`
  # over *non- ASCII* quotes. Both are currently O(N) in terms
  # of iterations only; they do a lot of other work besides
  # iteration as well.
  #
  # When you are slow, being even more slower doesn't matter
  # that much anymore. This is the case with Novika.
  #
  # And yes, quotes do rely on the experimental grapheme API.
  module Quote
    include Form

    # Creates a quote variant from *string*.
    #
    # *count* can be provided if the amount of graphemes in
    # *string* is known.
    def self.new(string : String, count = string.grapheme_size, ascii = string.ascii_only?)
      if count == 1
        string.each_grapheme { |it| return GraphemeQuote.new(it) }
      end

      StringQuote.new(string, count, ascii)
    end

    def desc(io : IO)
      io << "quote '" << string << "'"
    end

    def self.typedesc
      "quote"
    end

    # Converts this quote variant to `String`.
    abstract def string : String

    # Returns the grapheme at *index* as `Quote`, or nil.
    abstract def at?(index : Int32) : Quote?

    # Returns whether this quote variant consists of the same
    # graphemes as *other*.
    abstract def ==(other : Quote) : Bool

    # Returns the amount of graphemes in this quote variant.
    abstract def count : Int32

    # Returns the cached count of graphemes in this quote
    # variant. Returns nil if there is no cached count.
    abstract def cached_count? : Int32?

    # Returns whether this quote is empty.
    abstract def empty? : Bool

    # Slices this quote variant at *slicept*.
    #
    # *size* is the `count` of this quote.
    #
    # By invoking this method, `Quote` guarantees that *slicept*
    # is in bounds (not at the edges `0` or `count`), and that
    # the receiver quote is at least one character long.
    protected abstract def slice_at!(slicept : Int32, size : Int32) : {Quote, Quote}?

    # Stitches (concatenates) this and *other* quote variants,
    # and returns the resulting quote.
    def stitch(other : Quote) : Quote
      return other if empty?
      return self if other.empty?

      a = cached_count?
      b = other.cached_count?

      if a && b
        # If cached counts are available, add them to get the
        # resulting count.
        StringQuote.new(string + other.string, count: a + b)
      else
        # Maybe there is a faster way, maybe there isn't. Looking
        # at the implementation of `String#+`, there may be one.
        StringQuote.new(res = string + other.string, count: res.grapheme_size)
      end
    end

    # Slices this quote into two quotes at *slicept*. Returns
    # the two resulting quotes. Dies if *slicept* is out
    # of bounds.
    def slice_at(slicept : Int32) : {Quote, Quote}
      slice_at?(slicept) || die("slicepoint is out of bounds: #{slicept}")
    end

    # Slices this quote into two quotes at *slicept*. Returns
    # the two resulting quotes. Returns nil if *slicept* is out
    # of bounds.
    def slice_at?(slicept : Int32) : {Quote, Quote}?
      size = count

      return if size.zero?
      return unless slicept.in?(0..size)

      if slicept.zero?
        {StringQuote.new("", count: 0, ascii_only: true), self}
      elsif slicept == size
        {self, StringQuote.new("", count: 0, ascii_only: true)}
      else
        slice_at!(slicept, size)
      end
    end

    # Returns the grapheme at *index* as `Quote`, or dies.
    def at(index : Int32) : Quote
      at?(index) || die("grapheme index out of bounds: #{index}")
    end

    def to_quote(engine : Engine) : Quote
      self
    end
  end

  # Quote type for multiple (two or more), or no graphemes.
  struct Quote::StringQuote
    include Quote

    # Returns the underlying string.
    getter string : String

    # Returns the cached perceived character count in this
    # string quote, or nil.
    getter? cached_count : Int32?

    # Returns whether this string quote consists of ASCII
    # characters only.
    getter? ascii_only : Bool

    # Creates a string quote from the given *string*.
    def initialize(@string : String, count @cached_count : Int32? = nil, @ascii_only = string.ascii_only?)
      @cached_count = @string.bytesize if ascii_only?
    end

    def self.typedesc
      "quote"
    end

    protected def slice_at!(slicept : Int32, size : Int32) : {Quote, Quote}?
      return {
        # Fast path. Also, this string is ASCII only, then its
        # substrings are also ASCII-only. This way, we avoid
        # a (possibly) O(N) String#ascii_only? call.
        Quote.new(string[...slicept], count: slicept, ascii: true),
        Quote.new(string[slicept..], count: size - slicept, ascii: true),
      } if ascii_only?

      lhs = uninitialized String
      rhs = uninitialized String
      lhs_ascii_only = true
      rhs_ascii_only = true

      # Note: we speculate that left half is *slicept*, and
      # right half is *size* - *slicept* bytes long. It may
      # not be if it has grapheme clusters.
      lhs = String.build(slicept) do |lhalf|
        half = lhalf
        rhs = String.build(size - slicept) do |rhalf|
          index = 0
          string.each_grapheme do |grapheme|
            half = rhalf if index == slicept
            half << grapheme
            if lhs_ascii_only && index < slicept
              lhs_ascii_only = !!grapheme.@cluster.as?(Char).try(&.ascii?)
            elsif rhs_ascii_only
              rhs_ascii_only = !!grapheme.@cluster.as?(Char).try(&.ascii?)
            end
            index += 1
          end
        end
      end

      {Quote.new(lhs, count: slicept, ascii: lhs_ascii_only),
       Quote.new(rhs, count: size - slicept, ascii: rhs_ascii_only)}
    end

    def at?(index : Int32) : Quote?
      return if index.negative?

      if ascii_only?
        return unless byte = string.byte_at?(index)
        char = byte < 0x80 ? byte.unsafe_chr : Char::REPLACEMENT
        return GraphemeQuote.new String::Grapheme.new(char)
      end

      string.each_grapheme.with_index do |it, idx|
        return GraphemeQuote.new(it) if idx == index
      end
    end

    def stitch(other : StringQuote)
      return super unless ascii_only? && other.ascii_only?

      StringQuote.new(res = string + other.string,
        count: res.bytesize,
        ascii_only: true
      )
    end

    def count : Int32
      cached_count? || string.grapheme_size
    end

    def empty? : Bool
      string.empty?
    end

    def ==(other : Quote) : Bool
      other.is_a?(StringQuote) && string == other.string
    end

    def to_s(io)
      io << "'"; string.dump_unquoted(io); io << "'"
    end
  end

  # Quote type for a single grapheme (perceived character).
  struct Quote::GraphemeQuote
    include Quote

    # Returns the grapheme.
    getter grapheme : String::Grapheme

    def initialize(@grapheme : String::Grapheme)
    end

    def self.typedesc
      "quote"
    end

    def string : String
      grapheme.to_s
    end

    def stitch(other : StringQuote) : Quote
      other.empty? ? self : super
    end

    def at?(index : Int32) : Quote?
      self if index.zero?
    end

    # :inherit:
    #
    # Grapheme quotes always return 1.
    def count : Int32
      1
    end

    # :inherit:
    #
    # Grapheme quotes always return 1.
    def cached_count? : Int32?
      1
    end

    # :inherit:
    #
    # Grapheme quotes always return false.
    def empty? : Bool
      false
    end

    def ==(other : Quote) : Bool
      other.is_a?(GraphemeQuote) && other.grapheme == grapheme
    end

    # Grapheme quotes can only be sliced at edges:
    #   * 'f' 0 sliceQuoteAt ==> '' 'f'
    #   * 'f' 1 sliceQuoteAt ==> 'f' ''
    #
    # Anything else is out of bounds. Hence grapheme quotes
    # always return nil.
    protected def slice_at!(slicept : Int32, size : Int32) : {Quote, Quote}?
    end

    def to_s(io)
      io << "'" << grapheme << "'"
    end
  end
end
