module Novika
  # Includers are Novika quotes, which are known as strings
  # in most other programming languages.
  #
  # Currently quotes are completely unoptimizied, other than
  # treating single `String::Grapheme`s separately from strings
  # of those, and caching grapheme counts here and there. But
  # when you are slow, being even more slower doesn't matter
  # that much anymore. This is the case with Novika.
  #
  # And yes, quotes do rely on an experimental API.
  module Quote
    include Form
    extend HasDesc

    # Creates a quote variant from *string*.
    #
    # *count* can be provided if the amount of graphemes in
    # *string* is known.
    def self.new(string : String, count = string.grapheme_size)
      if count == 1
        string.each_grapheme { |it| return GraphemeQuote.new(it) }
      end

      StringQuote.new(string, count)
    end

    def desc(io : IO)
      io << "a quote"
    end

    def self.desc(io : IO)
      io << "a quote"
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

    # Slices this quote variant at *index*.
    #
    # By invoking this method, `Quote` guarantees that *index*
    # is in bounds (not at the edges 0 or `count`), and that
    # the receiver quote is at least one character long.
    protected abstract def slice_at!(index : Int32) : {Quote, Quote}?

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
        StringQuote.new(string + other.string)
      end
    end

    # Slices this quote into two quotes at *index*. Returns
    # the two resulting quotes. Dies if *index* is out of bounds.
    def slice_at(index : Int32) : {Quote, Quote}
      slice_at?(index) || die("grapheme index is out of bounds: #{index}")
    end

    # Slices this quote into two quotes at *index*. Returns
    # the two resulting quotes. Returns nil if *index* is out
    # of bounds.
    def slice_at?(index : Int32) : {Quote, Quote}?
      size = count

      return if size.zero?
      return unless index.in?(0..size)

      if index.zero?
        {StringQuote.new("", count: 0), self}
      elsif index == size
        {self, StringQuote.new("", count: 0)}
      else
        slice_at!(index)
      end
    end

    # Returns the grapheme at *index* as `Quote`, or dies.
    def at(index : Int32) : Quote
      at?(index) || die("grapheme index out of bounds: #{index}")
    end

    def enquote(engine : Engine) : Quote
      self
    end
  end

  # Quote type for multiple (two or more), or no graphemes.
  struct Quote::StringQuote
    include Quote

    getter string : String
    getter? cached_count : Int32?

    # Creates a string quote from the given *string*.
    def initialize(@string : String, count @cached_count : Int32? = nil)
    end

    protected def slice_at!(index : Int32) : {Quote, Quote}?
      lhalf = ""
      rhalf = ""
      last = index

      string.each_grapheme.with_index do |it, idx|
        lhalf, rhalf = rhalf, lhalf if idx == index
        rhalf += it.to_s
        last = idx
      end

      {Quote.new(lhalf, count: index), Quote.new(rhalf, count: last)}
    end

    def at?(index : Int32) : Quote?
      return if index.negative?
      string.each_grapheme.with_index do |it, idx|
        return GraphemeQuote.new(it) if idx == index
      end
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
    protected def slice_at!(index : Int32) : {Quote, Quote}?
    end

    def to_s(io)
      io << "'" << grapheme << "'"
    end
  end
end
