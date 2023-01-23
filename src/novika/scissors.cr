# Scissors deal with cutting a source string into fragments,
# known as *unclassified forms*. They are then fed to an
# instance of `Classifier`, which determines whether an
# unclassified form is actually a decimal, quoted word,
# quote, etc. You can think of Scissors as a fancy split-
# by-whitespace.
#
# `Scissors` and `Classifier` are designed to work in tandem.
# Separating one from the other is possible and will work, but is
# not recommended unless you have read the source code of both.
struct Novika::Scissors
  private getter start : Int32

  def initialize(source : String)
    @reader = Char::Reader.new(source)
    @start = 0
    @cursor = 0
  end

  # Introduces a cutpoint (slicepoint): resets the length.
  @[AlwaysInline]
  private def cut
    @dot = nil
    @start = @reader.pos
    @cursor = start
  end

  # Grows the length.
  @[AlwaysInline]
  private def grow
    @cursor = @reader.pos
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

  # Returns the length of the current fragment.
  @[AlwaysInline]
  private def length
    @cursor - start
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

  # Saves scissors state, and tries to advance through (see `thru`)
  # *amt* consequtive *char*s. If there aren't *amt* consequtive *char*s,
  # returns false and restores the state to that before this method.
  # Otherwise, returns true and doesn't restore the state.
  private def nthru?(char : Char, amt : Int)
    tmp_pos = @reader.pos
    tmp_dot = @dot
    tmp_start = @start
    tmp_cursor = @cursor

    amt.times do
      unless chr == char
        @dot = tmp_dot
        @start = tmp_start
        @cursor = tmp_cursor
        @reader.pos = tmp_pos
        return false
      end
      thru
    end

    true
  end

  # Advances through (see `thru`) until an instance of *endswith*
  # which is *not* preceded by *escape* is found.
  #
  # *amt* is the amount of *endswith* characters to match.
  #
  # Raises if reached the end without matching *endswith*.
  @[AlwaysInline]
  private def thru(endswith : Char, escape = '\\', amt = 1)
    until at_end?
      thru if chr == escape
      if at_end?
        # May happen in cases like '\<EOF> or "\<EOF>
        raise Novika::Error.new(
          "excerpt ended suddenly: expected escape sequence, grapheme, \
           or ⸢#{endswith.to_s * amt}⸥")
      end
      thru
      if chr == endswith
        if amt == 1
          thru
        elsif !nthru?(endswith, amt)
          thru
          next
        end
        return
      end
    end

    raise Novika::Error.new("unterminated excerpt: no matching ⸢#{endswith.to_s * amt}⸥")
  end

  # Cuts the source string into a series of *unclassified forms*;
  # yields start byte index, byte length, and first dot `'.'` byte
  # index of each to the block.
  #
  # Dot byte index is yielded to save an O(N) search, which would
  # be otherwise required since '.' is handled specially by several
  # forms in Novika.
  def each(&)
    # Grapheme processing is inspired by String#each_grapheme_boundary,
    # which you can find at:
    #
    # https://github.com/crystal-lang/crystal/blob/2da3efc9a6af69ecf182101e24eda85479c01376/src/string/grapheme/grapheme.cr#L10
    state = String::Grapheme::Property::Start
    last_prop = String::Grapheme::Property::Start

    until at_end?
      prop = String::Grapheme::Property.from(chr)
      boundary, state = String::Grapheme.break?(last_prop, prop, state)
      last_prop = prop

      unless boundary
        # Unless at grapheme boundary, simply (inclusion-) skip
        # the character we're looking at.
        thru
        next
      end

      case it = chr
      when .whitespace?
        # In Novika, whitespace acts as the primary separator between
        # forms. It is otherwise skipped.
        while chr.whitespace?
          # Skip while there is whitespace. This resolves cases like
          # '\r\n', where there are multiple whitespace characters that
          # may or may not be captured by the machinery otherwise.
          yield start, length, @dot unless length.zero?
          advance
          cut
        end
      when '\'', '"'
        # Quotes and comments act like a separator, too, mainly because
        # they can contain other separators. Note that comments are not
        # ignored here; they are ignored by the block rather than here,
        # because their content still could be of relevance.
        yield start, length, @dot unless length.zero?
        cut
        if nthru?(it, amt: 3)
          thru endswith: it, amt: 3
          # Omit two quotes from the start and the end.
          #
          # This makes the rest of the system think '''s and """s are
          # simply 's and "s.
          yield start + 2, length - 4, @dot
        else
          thru endswith: it
          yield start, length, @dot
        end
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
      when '(', ')'
        # () are like single-character comments of themselves.
        # They are completely ignored. It is left unchecked  whether
        # one '(' has the matching ')'.
        yield start, length, @dot unless length.zero?
        cut
        thru
        cut
      when '.'
        # Remember where the first dot was. This is nil-led
        # in `cut`.
        @dot ||= @cursor
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
