module Novika
  # A representation for decimal numbers inside Novika.
  struct Decimal
    include Form
    extend HasDesc

    # Returns the underlying big decimal value.
    protected getter val : BigDecimal

    def initialize(@val : BigDecimal)
    end

    def initialize(object : String | Number)
      initialize(object.to_big_d)
    end

    def desc(io : IO)
      io << "decimal number " << val
    end

    def self.desc(io : IO)
      io << "a decimal number"
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
      die("conversion overflow when downgrading a decimal")
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
      Decimal.new(val.to_big_i % other.val.to_big_i)
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

    def to_s(io)
      io << val
    end

    def_equals_and_hash val
  end
end
