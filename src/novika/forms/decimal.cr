module Novika
  # A representation for decimal numbers inside Novika.
  class Decimal
    include Form
    include ValueForm

    # Returns the underlying big decimal value.
    protected getter val : BigDecimal

    def initialize(@val : BigDecimal)
    end

    def initialize(object : String | Number)
      initialize(object.to_big_d)
    end

    delegate :to_u8, :to_u16, :to_u32, :to_u64, to: val
    delegate :to_i8, :to_i16, :to_i32, :to_i64, to: val
    delegate :to_f32, :to_f64, to: val

    def desc(io : IO)
      io << "decimal number "

      to_s(io)
    end

    def self.typedesc
      "decimal"
    end

    # Returns the character corresponding to this decimal.
    def chr : Char
      to_i.chr
    end

    # Returns whether this decimal is in the bounds of `Int64`.
    def i64?
      val.scale.zero? && Int64::MIN <= val <= Int64::MAX
    end

    # Returns whether this decimal is zero.
    def zero? : Bool
      val.zero?
    end

    # Downgrades this decimal into an integer (`Int32`). Dies
    # if too large.
    def to_i : Int32
      val.to_i
    rescue OverflowError
      die("overflow when downgrading a decimal: this decimal is too big")
    end

    # Returns the sum of this and *other* decimal numbers.
    def +(other : Decimal) : Decimal
      Decimal.new(val + other.val)
    end

    # Returns the difference between this and *other* decimal numbers.
    def -(other : Decimal) : Decimal
      Decimal.new(val - other.val)
    end

    # Returns the product of this and *other* decimal numbers.
    def *(other : Decimal) : Decimal
      Decimal.new(val * other.val)
    end

    # Returns the quotient of this and *other* decimal numbers.
    def /(other : Decimal) : Decimal
      Decimal.new(val / other.val)
    end

    # Returns the remainder of this and *other* decimal numbers.
    def %(other : Decimal) : Decimal
      Decimal.new(val % other.val)
    end

    # Raises this decimal to the power of *other*.
    def **(other : Decimal) : Decimal
      if val.scale.zero? && other.val.scale.zero?
        return Decimal.new(val ** other.val.to_i64)
      end

      Decimal.new(val.to_f64 ** other.to_f64)
    end

    # Returns the square root of this decimal.
    def sqrt : Decimal
      Decimal.new(Math.sqrt(val))
    end

    # Returns whether this decimal is smaller than *other*.
    def <(other : Decimal) : Bool
      val < other.val
    end

    # Combines this and *other* decimals using bitwise and.
    def &(other : Decimal) : Decimal
      Decimal.new(val.value & other.val.value)
    end

    # Combines this and *other* decimals using bitwise or.
    def |(other : Decimal) : Decimal
      Decimal.new(val.value | other.val.value)
    end

    # Yields each bit in this decimal.
    def each_bit(& : Decimal ->)
      val.value.to_s(2).each_char do |char|
        next if char == '-'
        yield Decimal.new(char == '1' ? 1 : 0)
      end
    end

    # Rounds this decimal.
    def round : Decimal
      Decimal.new(val.round)
    end

    # Truncates this decimal.
    def trunc : Decimal
      Decimal.new(val.trunc)
    end

    # Rounds this decimal down.
    def floor : Decimal
      Decimal.new(val.floor)
    end

    # Rounds this decimal up.
    def ceil : Decimal
      Decimal.new(val.ceil)
    end

    # Treats this decimal as radians, and returns cosine.
    def rad_cos : Decimal
      Decimal.new(Math.cos(val))
    end

    # Treats this decimal as radians, and returns cosine.
    def rad_sin : Decimal
      Decimal.new(Math.sin(val))
    end

    # Returns *n*-th most significant bit
    def nth_ms_bit?(n : Decimal) : Decimal?
      str = val.value.to_s(2)
      nint = n.to_i
      return unless nint < str.size

      Decimal.new(str[nint + (val.negative? ? 1 : 0)]? == '1' ? 1 : 0)
    end

    # Returns *n*-th least significant bit
    def nth_ls_bit(n : Decimal) : Decimal
      Decimal.new(val.value.abs.bit(n.to_i))
    end

    # Returns the number of bits in this decimal.
    def bitcount : Decimal
      Decimal.new(val.value.bit_length)
    end

    # Asserts this decimal is in one of *ranges*. Dies if it isn't.
    def in(*ranges) : Decimal
      return self if ranges.any? &.includes?(val)

      message = String.build do |io|
        io << "decimal out of range: expected "
        if ranges.size > 1
          io << "any of: "
        end
        ranges.join(io, ", ") do |range|
          io << "[" << range.begin << "; " << range.end
          io << (range.exclusive? ? ")" : "]")
        end
      end

      die(message)
    end

    # Asserts this decimal is an integer. Dies if it isn't.
    def int : Decimal
      return self if integer?

      die("decimal is not an integer")
    end

    # Asserts this decimal is a positive integer (i.e., >= 0).
    # Dies if it isn't.
    def posint : Decimal
      return self if val >= 0 && integer?

      die("decimal is not a positive integer")
    end

    # Returns whether this decimal is an integer.
    def integer?
      val.trunc == val
    end

    def to_s(io)
      io << (integer? ? val.to_big_i : val)
    end

    def_equals_and_hash val
  end
end
