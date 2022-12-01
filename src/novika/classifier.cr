# `Classifier` brings *unclassified forms* to life.
#
# `Classifier` assigns types to fragments of Novika code: this
# fragment is a decimal, this one is a word, this one is a quote.
# Fragments are given to `Classifier` by `Scissors`, a small
# object specializing in this very thing: cutting a big blob
# of Novika code into fragments.
#
# `Scissors` and `Classifier` are designed to work in tandem.
# Separating one from the other is possible and will work, but
# is not recommended unless you read the source code of both.
struct Novika::Classifier
  # Returns the source code byte pointer used by this classifier.
  getter bytes

  # Returns the block used by this classifier.
  getter block

  # Initializes a classifier from the given *source* string and
  # Novika *Block*.
  def initialize(source : String, block : Novika::Block)
    initialize(source.to_unsafe, block)
  end

  # :nodoc:
  def initialize(@bytes : UInt8*, @ceiling : Novika::Block)
    @block = ceiling
  end

  private delegate :add, to: block

  # Creates an empty child block, and makes it the current block.
  private def nest
    @block = block.class.new(block)
  end

  # Adds the current block onto its parent's tape, and makes
  # that parent the current block.
  private def unnest
    @block.die("mismatched ']' in block") if @ceiling.same?(@block)
    @block = block.parent.tap &.add(block)
  end

  # Takes a byte slice starting at *start*, and of *count*
  # bytes in size; wraps it in a string without any kind of
  # interpretation. Returns the resulting string.
  private def build_raw(start, count)
    String.build do |io|
      start.upto(start + count - 1) do |index|
        io.write_byte(@bytes[index])
      end
    end
  end

  # Takes a byte slice starting at *start*, and of *count*
  # bytes in size, and wraps it in a string.
  #
  # Bytes in the slice are interpreted as quote contents.
  # For example, escape sequences are evaluated (unescaped).
  # Returns the resulting string.
  #
  # Assumes the quote is properly terminated.
  private def build_quote(start, count)
    String.build do |io|
      b = start
      e = start + count - 1

      while b <= e
        byte = bytes[b]

        # Advance after the byte.
        b += 1

        unless byte === '\\'
          io.write_byte(byte)
          next
        end

        case bytes[b]
        when '\\' then io << '\\'
        when '\'' then io << '\''
        when 'n'  then io << '\n'
        when 't'  then io << '\t'
        when 'r'  then io << '\r'
        when 'v'  then io << '\v'
        when 'e'  then io << '\e'
        else
          # Leave the "escape sequence" as-is.
          io.write_byte(byte)
          next
        end

        # Advance after the escaped character byte.
        b += 1
      end
    end
  end

  # Similar to `build_quote` but for comments.
  #
  # Assumes the comment is properly terminated.
  private def build_comment(start, count)
    String.build do |io|
      b = start
      e = start + count - 1

      while b <= e
        byte = bytes[b]
        b += 1

        unless byte === '\\'
          io.write_byte(byte)
          next
        end

        case bytes[b]
        when '\\' then io << '\\'
        when '"'  then io << '"'
        else
          # Leave the "escape sequence" as-is.
          io.write_byte(byte)
          next
        end

        b += 1
      end
    end
  end

  # Returns whether *byte* is a decimal digit 0-9.
  @[AlwaysInline]
  private def digit?(byte : UInt8)
    byte.in?('0'.ord..'9'.ord)
  end

  # Returns whether the subrange `b..e` is an integer decimal.
  #
  # *sign* toggles optional sign parsing.
  #
  # **Beware**: returns true if `b == e`. You should handle
  # your "empty" cases yourself.
  private def decimal?(b, e, sign = false)
    b.upto(e) do |index|
      byte = @bytes[index]

      # * : '0'..'9'
      next if digit?(byte)

      case index
      when b
        # 0 : '+', '-'
        return false unless sign
        return false unless byte === '+' || byte === '-'

        # For '+', '-', also make sure the following is true:
        #
        # '+'|'-'    '0'..'9'
        #
        return false unless index < e && digit?(@bytes[index + 1])
      when ..e - 1
        # 1..-2 : '_'
        return false unless byte === '_'
      else
        return false
      end
    end

    true
  end

  # Classifies the subrange starting at byte index *start*,
  # and *count* bytes long. *dot* is the byte index of `'.'`.
  #
  # These three arguments are assumed to come from `Scissors#cut`.
  #
  # This method does practically no bounds checks, is unsafe
  # and must be worked with carefully.
  def classify(start, count, dot) : Nil
    return if count.zero?

    byte = @bytes[start]

    case byte
    when '[' then nest
    when ']' then unnest
    when '#'
      # If count > 1, then this is a quoted word. Otherwise,
      # this is the word "#".
      if count > 1
        # Omit the number/pound/whatever sign.
        add Novika::QuotedWord.new(build_raw(start + 1, count - 1))
      else
        add Novika::Word.new("#")
      end
    when '\''
      # If start is '\'', then this is a quote. Omit the
      # ''s though.
      add Novika::Quote.new(build_quote(start + 1, count - 2))
    when '"'
      # If start is '"', add a comment to the current block
      # if it is empty and doesn't already have one.
      return if block.has_comment?
      return unless block.count.zero?
      # Omit the ""s.
      block.describe_with?(build_comment(start + 1, count - 2))
    else
      e = start + count - 1

      unless dot
        # If dot = nil and start..end is an optionally signed
        # decimal, then this is a decimal. Otherwise, this is
        # a word.
        frag = build_raw(start, count)
        if decimal?(start, e, sign: true)
          add Novika::Decimal.new(frag)
        else
          add Novika::Word.new(frag)
        end
        return
      end

      if start < dot < e && decimal?(start, dot - 1, sign: true) && decimal?(dot + 1, e)
        # If dot = I, I.in(start..end) (since e.g. `.2`, `2.`,
        # and derived are *invalid* decimals in Novika), and
        # if start...I is an optionally signed decimal, and
        # I + 1..end is an unsigned decimal, then this is
        # a decimal.
        add Novika::Decimal.new(build_raw(start, count))
      else
        # Otherwise, recurse on start...I and I + 1..end. Then
        # this is the word `.`.
        #
        # By definition, `dot` is the first dot in the unclassified
        # form. Therefore, there is no dot left of it; so don't
        # even bother looking there.
        classify(start, dot - start, dot: nil)
        add Novika::Word.new(".")
        classify(dot + 1, e - dot)
      end
    end
  end

  # Classifies the subrange starting at byte index *start*,
  # and *count* bytes long.
  def classify(start, count)
    dot = nil
    start.upto(start + count - 1) do |index|
      dot = index if @bytes[index] === '.'
    end
    classify(start, count, dot)
  end

  # Ends classification. Makes sure the ceiling block is closed.
  def end
    @block.die("missing ']'") unless @ceiling.same?(@block)
  end

  # Shorthand for `initialize` followed by `end`. Yields
  # the instance.
  def self.for(source : String, block : Novika::Block)
    classifier = new(source, block)
    yield classifier
    classifier.end
  end
end
