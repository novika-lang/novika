module Novika
  # A representation for decimal numbers inside Novika.
  struct Decimal
    extend HasDesc

    include Form

    # Returns the underlying big decimal value.
    getter val : BigDecimal

    def initialize(@val : BigDecimal)
    end

    def initialize(object)
      initialize(object.to_big_d)
    end

    # Downgrades this decimal into an integer (`Int32`). Dies
    # if this decimal is too large.
    def to_i
      val.to_i
    rescue OverflowError
      die("conversion overflow when downgrading a decimal")
    end

    def desc
      "decimal number #{val}"
    end

    # Returns the sum of this and *other* decimal numbers.
    def +(other)
      Decimal.new(val + other.val)
    end

    # Returns the difference between this and *other* decimal numbers.
    def -(other)
      Decimal.new(val - other.val)
    end

    # Returns the product of this and *other* decimal numbers.
    def *(other)
      Decimal.new(val * other.val)
    end

    # Returns the quotient of this and *other* decimal numbers.
    def /(other)
      Decimal.new(val / other.val)
    end

    # Returns the remainder of this and *other* decimal numbers.
    def %(other)
      Decimal.new(val.to_big_i % other.val.to_big_i)
    end

    # Returns whether this decimal is smaller than *other*.
    def <(other)
      val < other.val
    end

    def to_s(io)
      io << val
    end

    def self.desc(io)
      io << "a decimal number"
    end
  end
end
