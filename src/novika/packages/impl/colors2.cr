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
        r, g, b = color.rgb
        r.push(engine)
        g.push(engine)
        b.push(engine)
      end

      target.at("hsl", <<-END
      ( H S L -- C ): creates a Color form from three decimals
       Hue (0-360, degrees), Saturation (0-100, percents),
       Lightness (0-100, percents).

      Since color forms are stored as RGB colors, the HSL color
      is converted into RGB first.

      >>> 0 0 0 hsl
      === rgb(0, 0, 0)

      >>> 206 35 46 hsl
      === rgb(76, 123, 158)
      END
      ) do |engine|
        l = engine.stack.drop.assert(engine, Decimal).in(0..100).posint
        s = engine.stack.drop.assert(engine, Decimal).in(0..100).posint
        h = engine.stack.drop.assert(engine, Decimal).in(0..360).posint
        Color.hsl(h, s, l).push(engine)
      end

      target.at("getHSL", <<-END
      ( C -- H S L ): leaves Hue, Saturation, Lightness values
       for a Color Form.

      >>> 206 35 46 hsl
      === rgb(76, 123, 158)
      >>> getHSL
      === 206 35 46
      END
      ) do |engine|
        color = engine.stack.drop.assert(engine, Color)
        h, s, l = color.hsl
        h.push(engine)
        s.push(engine)
        l.push(engine)
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
