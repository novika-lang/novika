require "big"

module Novika
  # A representation for decimal numbers inside Novika.
  abstract struct Decimal
    include Form
    extend HasDesc

    # Initializes a decimal number from *number*.
    def self.new(number : Int128 | BigInt)
      LargeDecimal.new(number)
    end

    # :ditto:
    def self.new(number : Int)
      SmallDecimal.new(number)
    end

    # :ditto:
    def self.new(number : Float)
      DecimalFloat.new(number)
    end

    # Initializes a decimal number from *string*.
    def self.new(string : String) : Decimal
      if string.includes?('.')
        DecimalFloat.new(string)
      elsif i64 = string.to_i64?
        SmallDecimal.new(i64)
      else
        LargeDecimal.new(string)
      end
    end

    def desc(io : IO)
      io << "decimal number " << value
    end

    def self.desc(io : IO)
      io << "a decimal number"
    end

    # Returns the underlying numeric value.
    protected abstract def value : Int64 | BigInt | BigFloat

    # Returns whether this decimal is zero.
    def zero?
      value.zero?
    end

    # Negates this decimal.
    def - : Decimal
      self.class.new(-value)
    end

    # Returns the difference of this decimal from *other*.
    def -(other : Decimal) : Decimal
      self + -other
    end

    {% for op in %w(+ * / %) %}
      # Converts both operands to floats and applies the#
      # corresponding operation
      #
      # Note: this method is reached only when `DecimalInt` or
      # `DecimalFloat` couldn't handle `{{op}}` themselves.
      def {{op.id}}(other : Decimal) : Decimal
        to_float {{op.id}} other.to_float
      end
    {% end %}

    # Returns decimal float 0.
    def //(other : Decimal) : Decimal
      DecimalFloat.new(0)
    end

    # Returns whether this decimal is smaller than *other*.
    def <(other : Decimal) : Bool
      value < other.value
    end

    # Converts this decimal to `Int32`. Dies upon overflow.
    def to_i : Int32
      value.to_i32
    rescue OverflowError
      die("integer conversion overflow")
    end

    # Converts this decimal to `DecimalFloat`.
    def to_float
      DecimalFloat.new(value)
    end

    def to_s(io)
      io << value
    end
  end

  # Holds floating-point decimals.
  struct DecimalFloat < Decimal
    protected getter value : BigFloat

    def initialize(object)
      @value = object.to_big_f
    end

    {% for op in %w(+ * / %) %}
      # Applies `{{op.id}}` on this and *other* float values.
      def {{op.id}}(other : DecimalFloat) : DecimalFloat
        DecimalFloat.new(value {{op.id}} other.value)
      end
    {% end %}

    # Rounds the contents of this float and returns the
    # resulting `DecimalInt`.
    def round : DecimalInt
      rounded = value.round
      if Int64::MIN <= rounded <= Int64::MAX
        SmallDecimal.new(rounded)
      else
        LargeDecimal.new(rounded)
      end
    end

    # Truncates the contents of this float and returns the
    # resulting `DecimalInt`.
    def trunc : DecimalInt
      truncated = value.round
      if Int64::MIN <= truncated <= Int64::MAX
        SmallDecimal.new(truncated)
      else
        LargeDecimal.new(truncated)
      end
    end
  end

  # Holds integer decimals.
  abstract struct DecimalInt < Decimal
    # Small decimal together with large decimal leads to this
    # method being called.
    private def promote(other : LargeDecimal)
      yield to_large, other
    end

    # Large decimal together with small decimal leads to this
    # method being called.
    private def promote(other : SmallDecimal)
      yield self, other.to_large
    end

    {% for op in %w(+ * // %) %}
      # Promotes either type (*other* to `LargeDecimal` or self to
      # `LargeDecimal`) and applies the corresponding operator.
      def {{op.id}}(other : DecimalInt) : DecimalInt
        promote(other) { |a, b| a {{op.id}} b }
      end
    {% end %}

    # If self is divisible by *other*, returns `DecimalInt`
    # result, else, `DecimalFloat` result.
    def /(other : DecimalInt) : Decimal
      (self % other).zero? ? self // other : super
    end

    # Converts decimal to a large decimal.
    def to_large : LargeDecimal
      LargeDecimal.new(value)
    end

    # Returns self (integers are already round).
    def round : self
      self
    end

    # Returns self (integers are already truncated).
    def trunc : self
      self
    end
  end

  # Holds small (Int64) integers.
  struct SmallDecimal < DecimalInt
    protected getter value : Int64

    def initialize(object)
      @value = object.to_i64
    end

    # Adds with an overflow check, and promotes automatically
    # to `LargeDecimal` in case of an overflow.
    def +(other : SmallDecimal) : DecimalInt
      sum = value &+ other.value
      overflow = (value < 0 && other.value < 0 && sum >= 0) ||
                 (value >= 0 && other.value >= 0 && sum < 0)
      overflow ? to_large + other.to_large : SmallDecimal.new(sum)
    end

    # Multiplies with an overflow check, and promotes automatically
    # to `LargeDecimal` in case of an overflow.
    def *(other : SmallDecimal) : DecimalInt
      prod = value &* other.value
      overflow = !(value == 0 || other.value == 0) && value != prod / other.value
      overflow ? to_large * other.to_large : SmallDecimal.new(prod)
    end

    # Divides with an overflow check, and promotes automatically
    # to `LargeDecimal` in case of an overflow.
    def //(other : SmallDecimal) : DecimalInt
      if value == Int64::MIN && other.value == -1
        to_large // other.to_large
      else
        SmallDecimal.new(value // other.value)
      end
    end

    # Returns the remainder from dividing this by *other*.
    def %(other : SmallDecimal) : SmallDecimal
      SmallDecimal.new(value % other.value)
    end
  end

  # Holds large (BigInt) integers.
  struct LargeDecimal < DecimalInt
    protected getter value : BigInt

    def initialize(object)
      @value = object.to_big_i
    end

    {% for op in %w(+ * // %) %}
      # Applies `{{op.id}}` on this and *other* decimal values.
      def {{op.id}}(other : LargeDecimal) : LargeDecimal
        LargeDecimal.new(value {{op.id}} other.value)
      end
    {% end %}
  end
end
