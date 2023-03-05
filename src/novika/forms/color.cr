require "lch"

module Novika
  struct Color
    include Form

    # Returns red channel value decimal (0-255).
    getter r : Decimal

    # Returns green channel value decimal (0-255).
    getter g : Decimal

    # Returns blue channel value decimal (0-255).
    getter b : Decimal

    # Holds alpha channel value decimal (0-255).
    #
    # You can mutate this to set alpha, but do remember that
    # `Color` is a struct.
    property a : Decimal

    protected def initialize(@r, @g, @b, @a = Decimal.new(255))
    end

    # Returns a tuple of R, G, B channel values.
    def rgb : {Decimal, Decimal, Decimal}
      {r, g, b}
    end

    # Returns a tuple with H, S, L of this color.
    def hsl : {Decimal, Decimal, Decimal}
      h, s, l = Color.rgb2hsl(r.to_f64, g.to_f64, b.to_f64)

      {Decimal.new(h), Decimal.new(s), Decimal.new(l)}
    end

    # Returns a tuple with H, S, V of this color.
    def hsv : {Decimal, Decimal, Decimal}
      h, s, v = Color.rgb2hsv(r.to_f64, g.to_f64, b.to_f64)

      {Decimal.new(h), Decimal.new(s), Decimal.new(v)}
    end

    # Returns a tuple with L, C, H of this color.
    def lch : {Decimal, Decimal, Decimal}
      l, c, h = LCH.rgb2lch(r.to_i, g.to_i, b.to_i)

      {Decimal.new(l.round), Decimal.new(c.round), Decimal.new(h.round)}
    end

    # Returns the color closest to this color from *palette*.
    #
    # How close one color is to another is determined by their
    # distance in an HSV-backed coordinate system.
    def closest(palette : Array(Color))
      h, s, v = hsv
      palette.min_by do |other|
        h1, s1, v1 = other.hsv
        (h1 - h).to_f64**2 + (s1 - s).to_f64**2 + (v1 - v).to_f64**2
      end
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

    # Creates a `Color` from *r*ed (0 <= h <= 255), *g*reen
    # (0 <= g <= 255), *b*lue (0 <= b <= 255) channel values.
    def self.rgb(r : Decimal, g : Decimal, b : Decimal) : Color
      new(r, g, b)
    end

    # :ditto:
    def self.rgb(r, g, b)
      rgb(Decimal.new(r), Decimal.new(g), Decimal.new(b))
    end

    # Creates a `Color` from *h*ue (0 <= h <= 360, degrees),
    # *s*aturation (0 <= s <= 100, percents), and *l*ightness
    # (0 <= l <= 100, percents).
    def self.hsl(h : Decimal, s : Decimal, l : Decimal) : Color
      h = h.to_f64
      s = s.to_f64
      l = l.to_f64

      s /= 100
      l /= 100
      c = (1 - (2 * l - 1).abs) * s
      x = c * (1 - ((h / 60) % 2 - 1).abs)
      m = l - c/2

      if h.in?(0...60)
        rp, gp, bp = {c, x, 0}
      elsif h.in?(60...120)
        rp, gp, bp = {x, c, 0}
      elsif h.in?(120...180)
        rp, gp, bp = {0, c, x}
      elsif h.in?(180...240)
        rp, gp, bp = {0, x, c}
      elsif h.in?(240...300)
        rp, gp, bp = {x, 0, c}
      elsif h.in?(300...360)
        rp, gp, bp = {c, 0, x}
      end

      new(
        Decimal.new(((rp.not_nil! + m) * 255).round),
        Decimal.new(((gp.not_nil! + m) * 255).round),
        Decimal.new(((bp.not_nil! + m) * 255).round),
      )
    end

    # Returns an HSL tuple for an RGB color.
    protected def self.rgb2hsl(r, g, b)
      rp = r / 255
      gp = g / 255
      bp = b / 255
      cmax = {rp, gp, bp}.max
      cmin = {rp, gp, bp}.min
      delta = cmax - cmin

      if delta.zero?
        h = 0
      elsif cmax == rp
        h = 60 * (((gp - bp) / delta) % 6)
      elsif cmax == gp
        h = 60 * (((bp - rp) / delta) + 2)
      elsif cmax == bp
        h = 60 * (((rp - gp) / delta) + 4)
      end

      l = (cmax + cmin) / 2
      s = delta.zero? ? 0 : delta / (1 - (2 * l - 1).abs)

      {h.not_nil!.round, (s * 100).round, (l * 100).round}
    end

    # Creates a `Color` from *h*ue (0 <= h <= 360, degrees),
    # *s*aturation (0 <= s <= 100, percents), and *v*alue
    # (0 <= v <= 100, percents).
    def self.hsv(h, s, v) : Color
      h = h.to_f64
      s = s.to_f64
      v = v.to_f64

      s /= 100
      v /= 100

      c = v * s
      x = c * (1 - ((h / 60) % 2 - 1).abs)
      m = v - c

      if h.in?(0...60)
        rp, gp, bp = {c, x, 0}
      elsif h.in?(60...120)
        rp, gp, bp = {x, c, 0}
      elsif h.in?(120...180)
        rp, gp, bp = {0, c, x}
      elsif h.in?(180...240)
        rp, gp, bp = {0, x, c}
      elsif h.in?(240...300)
        rp, gp, bp = {x, 0, c}
      elsif h.in?(300...360)
        rp, gp, bp = {c, 0, x}
      end

      new(
        Decimal.new(((rp.not_nil! + m) * 255).round),
        Decimal.new(((gp.not_nil! + m) * 255).round),
        Decimal.new(((bp.not_nil! + m) * 255).round),
      )
    end

    # Returns an HSV tuple for an RGB color.
    protected def self.rgb2hsv(r, g, b)
      rp = r / 255
      gp = g / 255
      bp = b / 255
      cmax = {rp, gp, bp}.max
      cmin = {rp, gp, bp}.min
      delta = cmax - cmin

      if delta.zero?
        h = 0
      elsif cmax == rp
        h = 60 * (((gp - bp) / delta) % 6)
      elsif cmax == gp
        h = 60 * (((bp - rp) / delta) + 2)
      elsif cmax == bp
        h = 60 * (((rp - gp) / delta) + 4)
      end

      v = cmax
      s = cmax.zero? ? 0 : delta / cmax

      {h.not_nil!.round, (s * 100).round, (v * 100).round}
    end

    # Creates a `Color` from *l*ightness (0-100), *c*hroma
    # (0-132), *h*ue (0-360).
    def self.lch(l : Decimal, c : Decimal, h : Decimal) : Color
      l = l.to_f64
      c = c.to_f64
      h = h.to_f64
      r, g, b = LCH.lch2rgb(l, c, h)
      new(Decimal.new(r), Decimal.new(g), Decimal.new(b))
    end
  end
end
