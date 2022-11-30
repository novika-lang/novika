# Scissors deal with cutting a source string into fragments,
# known as *unclassified forms*. They are then fed to an
# instance of `Classifier`, which determines whether an
# unclassified form is actually a decimal, quoted word,
# quote, etc. You can think of Scissors as a fancy split-
# by-whitespace.
#
# `Scissors` and `Classifier` are designed to work in tandem.
# Separating one from the other is possible and will work, but
# is not recommended unless you read the source code of both.
struct Novika::Scissors
  private getter length = 0

  def initialize(source : String)
    @dot = nil
    @reader = Char::Reader.new(source)
  end

  # Introduces a cutpoint (slicepoint): resets the length.
  @[AlwaysInline]
  private def cut
    @dot = nil
    @length = 0
  end

  # Grows the length.
  @[AlwaysInline]
  private def grow
    @length += @reader.current_char_width
  end

  # Returns whether the reader is at the end of the source code.
  @[AlwaysInline]
  private def at_end?
    !@reader.has_next?
  end

  # Returns the current character, raises if none.
  @[AlwaysInline]
  private def chr
    @reader.current_char
  end

  # Returns the byte index of the current slicepoint (i. e. start
  # of current form).
  @[AlwaysInline]
  private def start
    @reader.pos - length
  end

  # Advances the reader to the next character, raises if none.
  @[AlwaysInline]
  private def advance
    @reader.next_char
  end

  # Advances, and grows the length; in other words, advances
  # *through* the current character.
  @[AlwaysInline]
  private def thru
    advance
    grow
  end

  # Advances through (see `thru`) until an instance of *endswith*
  # which is *not* preceded by *escape* is found.
  #
  # Raises if reached the end without matching *endswith*.
  @[AlwaysInline]
  private def thru(endswith : Char, escape = '\\')
    until at_end?
      thru if chr == escape
      thru
      if chr == endswith
        thru
        return
      end
    end

    raise Novika::Error.new("unterminated excerpt: no matching ｢#{endswith}｣")
  end

  # Cuts the source string into a series of *unclassified forms*;
  # yields start byte index, byte length, and first dot `'.'` byte
  # index of each to the block.
  #
  # Dot byte index is yielded to save an O(N) search, which would
  # be otherwise required since '.' is handled specially by several
  # forms in Novika.
  def each
    until at_end?
      case it = chr
      when .ascii_whitespace?
        # In Novika, whitespace acts as the primary separator between
        # forms. It is otherwise skipped.
        yield start, length, @dot unless length.zero?
        cut
        advance
      when '\'', '"'
        # Quotes and comments act like a separator, too, mainly because
        # they can contain other separators. Note that comments are not
        # ignored here; they are ignored by the block rather than here,
        # because their content still could be of relevance.
        yield start, length, @dot unless length.zero?
        cut
        thru endswith: it
        yield start, length, @dot
        cut
      when '[', ']'
        # Block brackets [] are special in that they don't require any
        # separator before or after; instead, they themselves are separators,
        # in this sense much like quotes, but for a different reason.
        yield start, length, @dot unless length.zero?
        cut
        thru
        yield start, length, @dot
        cut
      when '.'
        # Remember where the first dot was. This is nil-led
        # in `cut`.
        @dot ||= @reader.pos
        thru
      else
        # Everything else is simply skipped over, and, when a separator
        # is found, yielded to the block. Could be a word, could be a
        # decimal; we don't have the authority to decide that here.
        # Instead, Classifier makes such kinds of decisions.
        thru
      end
    end
    yield start, length, @dot unless length.zero?
  end

  # Cuts *source* into a series of *unclassified forms*; yields
  # start byte index and byte length of each to the block.
  def self.cut(source : String, & : Int32, Int32, Int32? ->)
    slicer = new(source)
    slicer.each { |start, count, dot| yield start, count, dot }
  end
end
