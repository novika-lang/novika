module Novika
  # A representation for decimal numbers inside Novika.
  struct Decimal
    include Form

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
      io << "decimal number " << val
    end

    def self.typedesc
      "decimal"
    end

    # Returns whether this decimal is in the bounds of `Intr64`.
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
      self - other * (self / other).floor
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

    # Treats this decimal as radians, and returns cosine.
    def rad_cos : Decimal
      Decimal.new(Math.cos(val))
    end

    # Treats this decimal as radians, and returns cosine.
    def rad_sin : Decimal
      Decimal.new(Math.sin(val))
    end

    # Asserts this decimal is in *range*. Dies if it isn't.
    def in(range) : Decimal
      return self if range.includes?(val)

      die("decimal out of range: expected #{range.begin} to: #{range.end}, got: #{self}")
    end

    # Asserts this decimal is a positive integer (i.e., >= 0).
    # Dies if it isn't.
    def posint : Decimal
      return self if val >= 0 && val == val.to_big_i

      die("decimal is not a positive integer: #{self}")
    end

    def to_s(io)
      io << val
    end

    def_equals_and_hash val
  end
end
