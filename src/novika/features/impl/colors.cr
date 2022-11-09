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
      ( R G B -- Cf ): creates a Color form from three decimals
       Red (0-255), Green (0-255), and Blue (0-255).

      ```
      36 255 255 rgb toQuote leaves: 'rgb(36, 255 ,255)'
      ```'
      END
      ) do |_, stack|
        b = stack.drop.a(Decimal).in(0..255).posint
        g = stack.drop.a(Decimal).in(0..255).posint
        r = stack.drop.a(Decimal).in(0..255).posint
        Color.rgb(r, g, b).onto(stack)
      end

      target.at("getRGB", <<-END
      ( Cf -- R G B ): leaves Red, Green, Blue values for a
       Color form.

      ```
      0 25 3 rgb "rgb(0, 25, 3)" getRGB leaves: [ 0 25 3 ]
      ```
      END
      ) do |_, stack|
        color = stack.drop.a(Color)
        r, g, b = color.rgb
        r.onto(stack)
        g.onto(stack)
        b.onto(stack)
      end

      target.at("hsl", <<-END
      ( H S L -- Cf ): creates a Color form from three decimals
       Hue (0-360, degrees), Saturation (0-100, percents),
       Lightness (0-100, percents).

      Since color forms are stored in RGB, the HSL color is
      first converted into RGB.

      ```
      206 35 46 hsl toQuote leaves: 'rgb(76, 123, 158)'
      ```
      END
      ) do |_, stack|
        l = stack.drop.a(Decimal).in(0..100).posint
        s = stack.drop.a(Decimal).in(0..100).posint
        h = stack.drop.a(Decimal).in(0..360).posint
        Color.hsl(h, s, l).onto(stack)
      end

      target.at("getHSL", <<-END
      ( Cf -- H S L ): leaves Hue, Saturation, Lightness for
       a Color form.

      ```
      206 35 46 hsl "rgb(76, 123, 158)" getHSL leaves: [ 206 35 46 ]
      ```
      END
      ) do |_, stack|
        color = stack.drop.a(Color)
        h, s, l = color.hsl
        h.onto(stack)
        s.onto(stack)
        l.onto(stack)
      end

      target.at("hsv", <<-END
      ( H S V -- Cf ): creates a Color form from three decimals
       Hue (0-360, degrees), Saturation (0-100, percents),
       Value (0-100, percents).

      Since color forms are stored in RGB, the HSV color is
      first converted into RGB.

      ```
      120 100 100 hsv toQuote leaves: 'rgb(0, 255, 0)'
      ```
      END
      ) do |_, stack|
        v = stack.drop.a(Decimal).in(0..100).posint
        s = stack.drop.a(Decimal).in(0..100).posint
        h = stack.drop.a(Decimal).in(0..360).posint
        Color.hsv(h, s, v).onto(stack)
      end

      target.at("getHSV", <<-END
      ( Cf -- H S V ): leaves Hue, Saturation, Value for a
       Color form.

      ```
      180 100 50 hsv "rgb(0,128,128)" getHSV leaves: [ 180 100 50 ]
      ```
      END
      ) do |_, stack|
        color = stack.drop.a(Color)
        h, s, v = color.hsv
        h.onto(stack)
        s.onto(stack)
        v.onto(stack)
      end

      target.at("lch", <<-END
      ( L C H -- Cf ): creates a Color form from three decimals
       Lightness (0-100), Chroma (0-132), Hue (0-360).

      Since color forms are stored as RGB, the LCH color is
      first converted into RGB.

      LCH colors are tricky to implement but very fun to use.
      That's why they're in Novika's standard library.

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

      ```
      78 74 133 lch $: color

      color toQuote leaves: 'rgb(122, 215, 85)'
      color getLCH leaves: [ 78 74 133 ]
      color getLCH lch toQuote leaves: 'rgb(122, 215, 85)''
      "And so on..."
      ```

      And here is a bad conversion. At first, though, for it
      does stabilize after a few rounds as it falls firmly
      into the sRGB color space.

      ```
      74 107 26 lch $: color
      color toQuote leaves: 'rgb(255, 154, 151)'

      "Note how many chroma units we lose! Plus, Lab and
       LCH have hue shift on chroma changes, hence 26 -> 25."
      color getLCH leaves: [ 74 41 25 ]

      color getLCH lch toQuote leaves: 'rgb(255, 154, 152)'

      color getLCH lch getLCH leaves: [ 74 41 25 ]
      "... and so on, conversion had stabilized ..."
      ```

      You don't necessarily have to think about this, because
      the resulting colors do look very similar, differing in
      points rather than magnitudes. Just be aware that the
      conversion method used by this word and `getLCH` is lossy
      in some cases.
      END
      ) do |_, stack|
        h = stack.drop.a(Decimal).in(0..360).posint
        c = stack.drop.a(Decimal).in(0..132).posint
        l = stack.drop.a(Decimal).in(0..100).posint
        Color.lch(l, c, h).onto(stack)
      end

      target.at("getLCH", <<-END
      ( Cf -- L C H ): leaves Lightness, Chroma, Hue for a Color
       form. Please read documentation for `lch` to understand
       why `a b c lch getLCH` might not leave `a b c`.

      ```
      78 74 133 lch toQuote leaves: 'rgb(122, 215, 85)'
      78 74 133 lch getLCH leaves: [ 78 74 133 ]

      74 107 26 lch toQuote leaves: 'rgb(255, 154, 152)'

      "Chroma lowered to fit into sRGB. Lab and LCH have hue
       shift on chroma changes, 26 -> 25"
      74 107 26 lch getLCH leaves: [ 74 41 25 ]
      ```
      END
      ) do |_, stack|
        color = stack.drop.a(Color)
        l, c, h = color.lch
        l.onto(stack)
        c.onto(stack)
        h.onto(stack)
      end

      target.at("withAlpha", <<-END
      ( Cf A -- Cf' ): leaves Color form with alpha channel
       set to Alpha (0-255).

      ```
      0 25 3 rgb toQuote leaves: 'rgb(0, 25, 3)'
      0 25 3 rgb 100 withAlpha toQuote leaves: 'rgba(0, 25, 3, 100)'
      ```
      END
      ) do |_, stack|
        alpha = stack.drop.a(Decimal).in(0..255).posint
        color = stack.drop.a(Color)
        color.a = alpha
        color.onto(stack)
      end

      target.at("getAlpha", <<-END
      ( Cf -- A ): leaves Alpha for the given Color form.

      ```
      0 25 3 rgb getAlpha leaves: 255 "Opaque = 255"
      0 25 3 rgb 100 withAlpha getAlpha leaves: 100
      ```
      END
      ) do |_, stack|
        color = stack.drop.a(Color)
        color.a.onto(stack)
      end

      target.at("fromPalette", <<-END
      ( Cf Pb -- Cc ): leaves the Closest color form to Color from
       a Palette block. How close the color is is determined by
       distance: the Closest color is that color in Palette block
       to which Color has least (minimum) distance.

      ```
      [ 0 0 0 rgb
        255 0 0 rgb
        0 255 0 rgb
        0 0 255 rgb
        255 255 255 rgb
      ] vals $: pal

      0 0 0 rgb pal fromPalette toQuote leaves: 'rgb(0, 0, 0)'
      76 175 80 rgb pal fromPalette "greenish" toQuote leaves: 'rgb(0, 255, 0)'
      220 237 200 rgb pal fromPalette "very light green" toQuote leaves: 'rgb(255, 255, 255)'
      74 20 140 rgb pal fromPalette "very dark purple" toQuote leaves: 'rgb(255, 0, 0)'
      ```
      END
      ) do |_, stack|
        palette = stack.drop.a(Block)
        color = stack.drop.a(Color)

        colors = [] of Color
        palette.each do |pcolor|
          colors << pcolor.a(Color)
        end

        color.closest(colors).onto(stack)
      end
    end
  end
end
