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
  # When you are slow, being even slower doesn't matter that much
  # anymore. This is the case with Novika.
  #
  # And yes, quotes do rely on the experimental grapheme API.
  module Quote
    include Form

    # The empty quote.
    EMPTY = StringQuote.new("", count: 0, ascii_only: true)

    # Creates a quote from *string*.
    #
    # *count* can be provided if the amount of graphemes in
    # *string* is known.
    def self.new(string : String, count = string.grapheme_size, ascii = string.ascii_only?)
      if count == 1
        string.each_grapheme { |it| return GraphemeQuote.new(it) }
      end

      StringQuote.new(string, count, ascii)
    end

    # Creates a quote from *grapheme*.
    def self.new(grapheme : String::Grapheme)
      GraphemeQuote.new(grapheme)
    end

    # Creates a quote from *char*.
    def self.new(char : Char)
      new(String::Grapheme.new(char))
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
    abstract def at?(index : Int32) : GraphemeQuote?

    # Returns a subquote from *b* to *e*. Clamps *b* and *e*
    # to bounds of this quote. Returns an empty quote if this
    # quote is empty without regarding *b* and *e*.
    #
    # Both ends are inclusive.
    abstract def at(b : Int32, e : Int32) : Quote

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

    # Replaces instances of *pattern* with *repl*. Returns
    # the resulting quote.
    abstract def replace_all(pattern : Quote, repl : Quote) : Quote

    # Pads this quote with *padder* until it becomes *total* perceived
    # characters long. The side where the padding should apply is specified
    # by *side*. Returns the resulting quote.
    abstract def pad(total : Int, padder : _, side : PadSide) : Quote

    # Ensures this quote is of *total* characters or less. In case of
    # overflow, truncates with *ellipsis*. If even *ellipsis* cannot
    # fit, truncates ellipsis so that it is of *total* characters.
    # Returns the resulting quote.
    abstract def fit(total : Int, ellipsis : _) : Quote

    # Slices this quote variant at *slicept*.
    #
    # *size* is the `count` of this quote.
    #
    # By invoking this method, `Quote` guarantees that *slicept*
    # is in bounds (not at the edges `0` or `count`), and that
    # the receiver quote is at least one character long.
    protected abstract def slice_at!(slicept : Int32, size : Int32) : {Quote, Quote}?

    # Returns an immutable  `Byteslice` representation of
    # this quote.
    def to_byteslice
      Byteslice.new(string.to_slice, mutable: false)
    end

    # Returns the first byte (or nil) in this quote.
    def first_byte? : UInt8?
      string.byte_at?(0)
    end

    # Returns the Unicode codepoint for the first character in
    # this quote, or nil if this quote is empty.
    def ord? : Int32?
      string[0].ord unless empty?
    end

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
        {EMPTY, self}
      elsif slicept == size
        {self, EMPTY}
      else
        slice_at!(slicept, size)
      end
    end

    # Returns the grapheme at *index* as `Quote`, or dies.
    def at(index : Int32) : GraphemeQuote
      at?(index) || die("grapheme index out of bounds")
    end

    def to_quote : Quote
      self
    end

    # Yields occurrences of the given *pattern* in this quote.
    def each_occurrence_of(pattern : Form, &)
    end

    # Specifies the maximum amount of characters to display before
    # the quote gets cut off in `effect` (see `Form#effect`).
    EFFECT_MAX_CHARS = 32

    # Specifies how many characters to take from the left and right
    # boundaries of the quote for a shorter representation in `effect`.
    EFFECT_BOUND_TAKE = 12

    def effect(io)
      nchars = count

      return super if nchars <= EFFECT_MAX_CHARS

      l = at(0, EFFECT_BOUND_TAKE)
      r = at(nchars - EFFECT_BOUND_TAKE - 1, nchars - 1)

      io << "'"; l.string.dump_unquoted(io)
      io << "…"; r.string.dump_unquoted(io)
      io << "'"
    end
  end

  # Represents the side where padding should apply.
  #
  # See `Quote#pad`.
  enum Quote::PadSide
    # Apply padding to the left of the quote.
    Left

    # Apply padding to the right of the quote.
    Right

    # Applies padding to the side specified by `self`.
    def apply(quote : Quote, padding : Quote)
      case self
      in .left?  then padding.stitch(quote)
      in .right? then quote.stitch(padding)
      end
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

    def at?(index : Int32) : GraphemeQuote?
      return if index.negative?

      if ascii_only?
        return unless byte = string.byte_at?(index)
        char = byte < 0x80 ? byte.unsafe_chr : Char::REPLACEMENT
        return GraphemeQuote.new String::Grapheme.new(char)
      end

      idx = 0
      string.each_grapheme do |it|
        return GraphemeQuote.new(it) if idx == index
        idx += 1
      end
    end

    def at(b : Int32, e : Int32) : Quote
      b = Math.max(b, 0)
      e = Math.min(e, count - 1)
      return self if b == 0 && e == count - 1
      return at?(b).not_nil! if b == e

      if ascii_only?
        StringQuote.new(
          (b..e).join do |index|
            byte = string.byte_at?(index).not_nil!
            byte < 0x80 ? byte.unsafe_chr : Char::REPLACEMENT
          end,
          count: e - b,
          ascii_only: true
        )
      else
        StringQuote.new(
          String.build do |io|
            index = 0
            string.each_grapheme do |grapheme|
              if index < b
                index += 1
                next
              end
              break if index > e
              io << grapheme
              index += 1
            end
          end,
          count: e - b,
          ascii_only: false
        )
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

    def pad(total : Int, padder : GraphemeQuote, side : PadSide) : Quote
      return self unless total > count

      if total == count + 1
        padding = padder
      else
        string = String.build(total) do |io|
          (total - count).times do
            io << padder.grapheme
          end
        end

        padding = StringQuote.new(string)
      end

      side.apply(self, padding)
    end

    def pad(total : Int, padder : StringQuote, side : PadSide) : Quote
      return self if padder.empty?
      return self unless total > count

      if total == count + 1
        padding = padder.at(0)
      else
        string = String.build(total) do |io|
          needed = total - count

          head = padder.at(0, Math.min(padder.count - 2, needed - 1))
          tail = padder.at(Math.min(padder.count - 1, needed)).string

          io << head.string
          (needed - head.count).times do
            io << tail
          end
        end

        padding = StringQuote.new(string)
      end

      side.apply(self, padding)
    end

    def fit(total : Int, ellipsis : Quote) : Quote
      return StringQuote.new("") if total == 0
      return self if count <= total

      nvisible = total - ellipsis.count

      # Even the ellipsis doesn't fit. Truncate it and output it instead.
      return ellipsis.at(0, total - 1) if nvisible <= 0

      at(0, nvisible - 1).stitch(ellipsis)
    end

    def each_occurrence_of(pattern : GraphemeQuote, &)
      index = 0

      # Pattern is a single grapheme. There are two ways to go now:
      #
      # * If this string is ASCII and pattern is ASCII, iterate by
      #   bytes (the fastest way!) and yield byte indices.
      #
      # * Otherwise, find through the slow each_grapheme process.
      if ascii_only? && (pattern_byte = pattern.as_byte?)
        string.each_byte do |byte|
          yield index if byte == pattern_byte
          index += 1
        end
      else
        string.each_grapheme do |grapheme|
          yield index if grapheme == pattern.grapheme
          index += 1
        end
      end
    end

    def each_occurrence_of(pattern : StringQuote)
      kmp(string, pattern.string, ascii: ascii_only? && pattern.ascii_only?) do |index|
        yield index
      end
    end

    # Knuth-Morris-Pratt string matching algorithm.
    #
    # *ascii* determines whether both haystack and needle are ASCII.
    #
    # Translated from here:
    #
    # https://github.com/dryruner/string_matching/blob/ef67b9e964af5d75a57cf6ee2ebb4c42365aaac2/string_matching.c#L99
    #
    # I do not understand what any of this means. To people who
    # name their variables 'i' and 'q', THIS IS NOT MATH!!!
    private def kmp(haystack_s : String, needle_s : String, ascii = false)
      if ascii
        haystack = haystack_s.to_slice
        needle = needle_s.to_slice
      else
        haystack = haystack_s.graphemes
        needle = needle_s.graphemes
      end

      prefixes = Array(Int32).new(needle.size, 0)
      k = 0

      # Compute prefix array
      2.upto(needle.size) do |q|
        while k > 0 && needle[k] != needle[q - 1]
          k = prefixes[k - 1]
        end
        if needle[k] == needle[q - 1]
          k += 1
        end
        prefixes[q - 1] = k
      end

      q = 0
      haystack.size.times do |i|
        while q > 0 && needle[q] != haystack[i]
          q = prefixes[q - 1]
        end
        if needle[q] == haystack[i]
          q += 1
        end
        if q == needle.size # Match!
          yield i - needle.size + 1
          # For the next match
          q = prefixes[q - 1]
        end
      end
    end

    def replace_all(pattern : Quote, repl : Quote) : Quote
      Quote.new(string.gsub(pattern.string, repl.string))
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

    def as_byte?
      return unless char = grapheme.@cluster.as?(Char)
      return unless char.ascii?
      char.ord
    end

    def string : String
      grapheme.to_s
    end

    def stitch(other : StringQuote) : Quote
      other.empty? ? self : super
    end

    def at?(index : Int32) : GraphemeQuote?
      self if index.zero?
    end

    def at(b : Int32, e : Int32) : Quote
      b == e ? self : EMPTY
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

    def pad(total : Int, padder : GraphemeQuote, side : PadSide) : Quote
      return self if total <= 1

      if total == 2
        padding = padder
      else
        string = String.build do |io|
          last = padder.grapheme
          (total - 1).times do
            io << last
          end
        end

        padding = StringQuote.new(string)
      end

      side.apply(self, padding)
    end

    def pad(total : Int, padder : StringQuote, side : PadSide) : Quote
      return self if padder.empty?
      return self if total <= 1

      if total == 2
        padding = padder.at(0)
      else
        string = String.build(total) do |io|
          needed = total - 1

          head = padder.at(0, Math.min(padder.count - 2, needed - 1))
          tail = padder.at(Math.min(padder.count - 1, needed)).string

          io << head.string
          (needed - head.count).times do
            io << tail
          end
        end

        padding = StringQuote.new(string)
      end

      side.apply(self, padding)
    end

    def fit(total : Int, ellipsis : Quote) : Quote
      return StringQuote.new("") if total == 0

      self
    end

    def each_occurrence_of(pattern : GraphemeQuote, &)
      if grapheme == pattern.grapheme
        yield 0
      end
    end

    def each_occurrence_of(pattern : StringQuote, &)
    end

    # Grapheme quotes can only be sliced at edges:
    #   * 'f' 0 sliceQuoteAt ==> '' 'f'
    #   * 'f' 1 sliceQuoteAt ==> 'f' ''
    #
    # Anything else is out of bounds. Hence grapheme quotes
    # always return nil.
    protected def slice_at!(slicept : Int32, size : Int32) : {Quote, Quote}?
    end

    def replace_all(pattern : Quote, repl : Quote) : Quote
      self == pattern ? repl : self
    end

    def to_s(io)
      io << "'"; grapheme.to_s.dump_unquoted(io); io << "'"
    end
  end
end
