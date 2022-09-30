module Novika::Features::Impl
  class Colors
    include Feature

    def self.id : String
      "colors"
    end

    def self.purpose : String
      "exposes vocabulary for working with colors"
    end

    def self.on_by_default? : Bool
      true
    end

    def inject(into target : Block)
      target.at("rgb", <<-END
      ( R G B -- C ): creates a Color form from three decimals
       Red (0-255), Green (0-255), and Blue (0-255).

      >>> 36 255 255 rgb
      === rgb(36, 255 ,255)
      END
      ) do |engine, stack|
        b = stack.drop.assert(engine, Decimal).in(0..255).posint
        g = stack.drop.assert(engine, Decimal).in(0..255).posint
        r = stack.drop.assert(engine, Decimal).in(0..255).posint
        Color.rgb(r, g, b).onto(stack)
      end

      target.at("getRGB", <<-END
      ( C -- R G B ): leaves Red, Green, Blue values for a
       color Form.

      >>> 0 25 3 rgb
      === rgb(0, 25, 3)
      >>> getRGB
      === 0 25 3
      END
      ) do |engine, stack|
        color = stack.drop.assert(engine, Color)
        r, g, b = color.rgb
        r.onto(stack)
        g.onto(stack)
        b.onto(stack)
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
      ) do |engine, stack|
        l = stack.drop.assert(engine, Decimal).in(0..100).posint
        s = stack.drop.assert(engine, Decimal).in(0..100).posint
        h = stack.drop.assert(engine, Decimal).in(0..360).posint
        Color.hsl(h, s, l).onto(stack)
      end

      target.at("getHSL", <<-END
      ( C -- H S L ): leaves Hue, Saturation, Lightness for
       a Color Form.

      >>> 206 35 46 hsl
      === rgb(76, 123, 158)
      >>> getHSL
      === 206 35 46
      END
      ) do |engine, stack|
        color = stack.drop.assert(engine, Color)
        h, s, l = color.hsl
        h.onto(stack)
        s.onto(stack)
        l.onto(stack)
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
      ) do |engine, stack|
        v = stack.drop.assert(engine, Decimal).in(0..100).posint
        s = stack.drop.assert(engine, Decimal).in(0..100).posint
        h = stack.drop.assert(engine, Decimal).in(0..360).posint
        Color.hsv(h, s, v).onto(stack)
      end

      target.at("getHSV", <<-END
      ( C -- H S L ): leaves Hue, Saturation, Value for a
       Color Form.

      >>> 180 100 50 hsv
      === rgb(0,128,128)
      >>> getHSV
      === 180 100 50
      END
      ) do |engine, stack|
        color = stack.drop.assert(engine, Color)
        h, s, v = color.hsv
        h.onto(stack)
        s.onto(stack)
        v.onto(stack)
      end

      target.at("lch", <<-END
      ( L C H -- C ): creates a Color form from three decimals
       Lightness (0-100), Chroma (0-132), Hue (0-360).

      Since color forms are stored as RGB, the LCH color is
      first converted into RGB.

      LCH colors are *very* hard but very fun to use. That's
      why they're in Novika.

      CIELAB encloses more colors than sRGB, so some conversion
      imprecisions *are* to be expected because some colors just
      fall out of sRGB gamut (lossiness is especially noticeable
      in LCH -> RGB -> LCH conversions, but it stabilizes on the
      last step because the last step's LCH is guraranteed to be
      inside the sRGB gamut).

      Any color out of the sRGB gamut is brought into the sRGB
      gamut by lowering chroma until it's in the sRGB bounds.

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

      And here is a bad conversion. At first, though, for it
      does stabilize after a few rounds as it falls firmly
      into the sRGB color space.

      >>> 74 107 26 lch
      === rgb(255, 154, 151)
      >>> getLCH
      "Note how many chroma units we've lost! Plus, Lab and
       LCH have hue shift on chroma changes, hence 26 -> 25."
      === 74 41 25
      >>> lch
      === rgb(255, 154, 152)
      >>> getLCH
      === 74 41 25
      >>> lch
      === rgb(255, 154, 152)
      >>> getLCH
      === 74 41 25
      "... and so on, conversion stabilized ..."

      You don't necessarily have to think about this, because
      the resulting colors do look similar enough. Just beware
      that the conversion method used by this word and `getLCH`
      is lossy sometimes.
      END
      ) do |engine, stack|
        h = stack.drop.assert(engine, Decimal).in(0..360).posint
        c = stack.drop.assert(engine, Decimal).in(0..132).posint
        l = stack.drop.assert(engine, Decimal).in(0..100).posint
        Color.lch(l, c, h).onto(stack)
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
      === rgb(255, 154, 152)
      >>> getLCH
      "Chroma lowered to fit into sRGB. Lab and LCH have hue
       shift on chroma changes, 26 -> 25"
      === 74 41 25
      END
      ) do |engine, stack|
        color = stack.drop.assert(engine, Color)
        l, c, h = color.lch
        l.onto(stack)
        c.onto(stack)
        h.onto(stack)
      end

      target.at("withAlpha", <<-END
      ( C A -- C' ): leaves Color with alpha channel set to
       Alpha (0-255).

      >>> 0 25 3 rgb
      === rgb(0, 25, 3)
      >>> 100 withAlpha
      === rgba(0, 25, 3, 100)
      END
      ) do |engine, stack|
        alpha = stack.drop.assert(engine, Decimal).in(0..255).posint
        color = stack.drop.assert(engine, Color)
        color.a = alpha
        color.onto(stack)
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
      ) do |engine, stack|
        color = stack.drop.assert(engine, Color)
        color.a.onto(stack)
      end

      target.at("fromPalette", <<-END
      ( C Pb -- Cl ): leaves the Closest color form to Color from
       a Palette block. Closeness is determined by distance: the
       Closest color is that color in Palette block to which Color
       has least (minimum) distance.

      >>> [ ] [ 0 0 0 rgb
            255 0 0 rgb
            0 255 0 rgb
            0 0 255 rgb
            255 255 255 rgb
          ] there $: pal
      >>> 0 0 0 rgb pal fromPalette
      === rgb(0, 0, 0)
      >>> 76 175 80 rgb pal fromPalette "greenish"
      === rgb(0, 255, 0)
      >>> 220 237 200 rgb pal fromPalette "very light green"
      === rgb(255, 255, 255)
      >>> 74 20 140 rgb pal fromPalette "very dark purple"
      === rgb(255, 0, 0)
      END
      ) do |engine, stack|
        palette = stack.drop.assert(engine, Block)
        color = stack.drop.assert(engine, Color)

        colors = [] of Color
        palette.each do |pcolor|
          colors << pcolor.assert(engine, Color)
        end

        color.closest(colors).onto(stack)
      end
    end
  end
end
