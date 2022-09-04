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
      ( C -- R G B ): leaves Red, Green, Blue values for a
       color Form.

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

      Since color forms are stored in RGB, the HSL color is
      first converted into RGB.

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
      ( C -- H S L ): leaves Hue, Saturation, Lightness for
       a Color Form.

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

      target.at("hsv", <<-END
      ( H S V -- C ): creates a Color form from three decimals
       Hue (0-360, degrees), Saturation (0-100, percents),
       Lightness (0-100, percents).

      Since color forms are stored in RGB, the HSV color is
      first converted into RGB.

      >>> 120 100 100 hsv
      === rgb(0, 255, 0)
      END
      ) do |engine|
        v = engine.stack.drop.assert(engine, Decimal).in(0..100).posint
        s = engine.stack.drop.assert(engine, Decimal).in(0..100).posint
        h = engine.stack.drop.assert(engine, Decimal).in(0..360).posint
        Color.hsv(h, s, v).push(engine)
      end

      target.at("getHSV", <<-END
      ( C -- H S L ): leaves Hue, Saturation, Value for a
       Color Form.

      >>> 180 100 50 hsv
      === rgb(0,128,128)
      >>> getHSV
      === 180 100 50
      END
      ) do |engine|
        color = engine.stack.drop.assert(engine, Color)
        h, s, v = color.hsv
        h.push(engine)
        s.push(engine)
        v.push(engine)
      end

      target.at("lch", <<-END
      ( L C H -- C ): creates a Color form from three decimals
       Lightness (0-100), Chroma (0-132), Hue (0-360).

      Since color forms are stored as RGB, the LCH color is
      first converted into RGB.

      LCH colors are *very* hard but very fun to use. That's
      why they're in Novika.

      LCH encloses more colors than RGB, so some conversion
      imprecisions *are* to be expected because they fall out
      of RGB range, and therefore are clamped into RGB (meaning
      conversion is lossy, and sometimes very lossy).

      The conversions here, even though mathematically imprecise
      (or outright incorrect), do give out colors that look the
      same, and that's good enough.

      Here is a 'good' conversion, meaning it nicely closes
      on itself:

      >>> 78 74 133 lch
      === rgb(122, 215, 85)
      >>> getLCH
      === 78 74 133
      >>> lch
      === rgb(122, 215, 85)
      >>> getLCH
      === 78 74 133
      ... and so on ...

      And here is a very bad conversion. At first, though, for
      it does stabilize after a few rounds as it falls firmly
      into the RGB color space.

      >>> 74 107 26 lch
      === rgb(255, 61, 103)
      >>> getLCH
      === 58 77 17 "Note how many units we've lost!"
      >>> lch
      === rgb(255, 62, 104)
      >>> getLCH
      === 58 76 17
      >>> lch
      === rgb(255, 64, 105)
      >>> getLCH
      === 58 76 17
      ... and so on, conversion stabilized ...

      You don't necessarily have to think about this, because
      the resulting colors do look similar enough. Just beware
      that the conversion method used by this word and `getLCH`
      is lossy and dumb in terms of choosing a fallback RGB
      color which yields low enough delta when doing LCH ->
      RGB -> LCH.
      END
      ) do |engine|
        h = engine.stack.drop.assert(engine, Decimal).in(0..360).posint
        c = engine.stack.drop.assert(engine, Decimal).in(0..132).posint
        l = engine.stack.drop.assert(engine, Decimal).in(0..100).posint
        Color.lch(l, c, h).push(engine)
      end

      target.at("getLCH", <<-END
      ( C -- L C H ): leaves Lightness, Chroma, Hue for a Color
       form. Please read documentation for `lch` to understand
       why `a b c lch getLCH` might not leave `a b c`.

      >>> 78 74 133 lch
      === rgb(122, 215, 85)
      >>> getLCH
      === 78 74 133

      >>> 74 107 26 lch
      === rgb(255, 61, 103)
      >>> getLCH
      === 58 77 17 "Note how many units we've lost! See `lch`"
      END
      ) do |engine|
        color = engine.stack.drop.assert(engine, Color)
        l, c, h = color.lch
        l.push(engine)
        c.push(engine)
        h.push(engine)
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
