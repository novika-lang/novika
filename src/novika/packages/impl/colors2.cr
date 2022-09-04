module Novika::Packages::Impl
  class Colors2
    include Package

    def self.id : String
      "colors2"
    end

    def self.purpose : String
      "vocabulary for working with colors"
    end

    def self.on_by_default? : Bool
      true
    end

    def inject(into target : Block)
      target.at("rgb", <<-END
      ( R G B -- C ): creates a color form from three decimals
       Red (0-255), Green (0-255), and Blue (0-255).

      >>> 0 0 0 rgb
      === rgb(0, 0 ,0)

      >>> 36 255 255 rgb
      === rgb(36, 255 ,255)
      END
      ) do |engine|
        b = engine.stack.drop.assert(engine, Decimal).in(0..255).posint
        g = engine.stack.drop.assert(engine, Decimal).in(0..255).posint
        r = engine.stack.drop.assert(engine, Decimal).in(0..255).posint
        Color.rgb(r, g, b).push(engine)
      end

      target.at("getRGB", <<-END
      ( C -- R G B ): leaves Red, Green, Blue channel values
       for a color Form.

      >>> 0 25 3 rgb
      === rgb(0, 25, 3)
      >>> getRGB
      === 0 25 3
      END
      ) do |engine|
        color = engine.stack.drop.assert(engine, Color)
        color.r.push(engine)
        color.g.push(engine)
        color.b.push(engine)
      end

      target.at("withAlpha", <<-END
      ( C A -- C' ): leaves Color with alpha channel set to
       Alpha (0-255).

      >>> 0 25 3 rgb
      === rgb(0, 25, 3)
      >>> 100 withAlpha
      === rgba(0, 25, 3, 100)
      END
      ) do |engine|
        alpha = engine.stack.drop.assert(engine, Decimal).in(0..255).posint
        color = engine.stack.drop.assert(engine, Color)
        color.a = alpha
        color.push(engine)
      end

      target.at("getAlpha", <<-END
      ( C -- A ): leaves Alpha for the given Color form.

      >>> 0 25 3 rgb
      === rgb(0, 25, 3)
      >>> getAlpha
      === 255

      >>> 0 25 3 rgb
      === rgb(0, 25, 3)
      >>> 100 withAlpha
      === rgba(0, 25, 3, 100)
      >>> getAlpha
      === 100
      END
      ) do |engine|
        color = engine.stack.drop.assert(engine, Color)
        color.a.push(engine)
      end
    end
  end
end
