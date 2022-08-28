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
    def self.new(string : String, count = string.grapheme_size, ascii = string.ascii_only?)
      if count == 1
        string.each_grapheme { |it| return GraphemeQuote.new(it) }
      end

      StringQuote.new(string, count, ascii)
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

    # Slices this quote variant at *slicept*.
    #
    # By invoking this method, `Quote` guarantees that *slicept*
    # is in bounds (not at the edges `0` or `count`), and that
    # the receiver quote is at least one character long.
    protected abstract def slice_at!(slicept : Int32) : {Quote, Quote}?

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
        slice_at!(slicept)
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

    protected def slice_at!(slicept : Int32) : {Quote, Quote}?
      return {
        # Fast path. Also, this string is ASCII only, then its
        # substrings are also ascii-only. This way, we avoid
        # a (possibly) O(N) String#ascii_only? call.
        Quote.new(string[...slicept], count: slicept, ascii: true),
        Quote.new(string[slicept..], count: count - slicept, ascii: true),
      } if ascii_only?

      # We always know the size of the left half: it's `slicept`.
      lhalf = IO::Memory.new(slicept)

      # If we know the size of the right half, good, but we
      # may not always know it. In that case, use string bytesize
      # as a "good enough" heuristic. One (probably single,
      # actually) benefit it will at all times be > than the
      # amount of preceived characters, or = in case of an
      # ASCII-only string.
      #
      # Of course sometimes it will use (a lot) more memory
      # than it needs.
      rhalf = IO::Memory.new((cached_count? || string.bytesize) - slicept)

      half = lhalf
      index = 0

      string.each_grapheme do |grapheme|
        half = rhalf if index == slicept
        half << grapheme
        index += 1
      end

      {Quote.new(lhalf.to_s, count: slicept),
       Quote.new(rhalf.to_s, count: index - slicept)}
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
    protected def slice_at!(slicept : Int32) : {Quote, Quote}?
    end

    def to_s(io)
      io << "'" << grapheme << "'"
    end
  end
end
