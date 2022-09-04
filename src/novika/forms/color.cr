module Novika
  struct Color
    include Form

    # Returns decimal for red channel value (0-255).
    getter r : Decimal

    # Returns decimal for green channel value (0-255).
    getter g : Decimal

    # Returns decimal for blue channel value (0-255).
    getter b : Decimal

    # Holds decimal for alpha channel value (0-255).
    #
    # You can mutate this to set alpha, but remember that
    # `Color` is a struct.
    property a : Decimal

    def initialize(@r, @g, @b, @a = Decimal.new(255))
    end

    # Creates a `Color` from RGB.
    def self.rgb(r, g, b)
      new(r, g, b)
    end

    def self.typedesc
      "color"
    end

    def desc(io)
      to_s(io)
    end

    def to_s(io)
      a255 = Decimal.new(255)

      io << "rgb"
      io << "a" unless a == a255
      io << "(" << r << ", " << g << ", " << b
      io << ", " << a unless a == a255
      io << ")"
    end
  end
end
