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

    # Returns a tuple of R, G, B channel values.
    def rgb : {Decimal, Decimal, Decimal}
      {r, g, b}
    end

    # Returns a tuple of H, S, L channel values.
    def hsl : {Decimal, Decimal, Decimal}
      r = self.r.to_big_i
      g = self.g.to_big_i
      b = self.b.to_big_i

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

      {Decimal.new(h.not_nil!.round),
       Decimal.new(s * 100).round,
       Decimal.new(l * 100).round}
    end

    # Returns a tuple of H, S, V channel values.
    def hsv : {Decimal, Decimal, Decimal}
      r = self.r.to_big_i
      g = self.g.to_big_i
      b = self.b.to_big_i

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

      {Decimal.new(h.not_nil!.round),
       Decimal.new(s * 100).round,
       Decimal.new(v * 100).round}
    end

    # Creates a `Color` from RGB.
    def self.rgb(r, g, b) : Color
      new(r, g, b)
    end

    # Creates a `Color` from *h*ue (0 <= h <= 360, degrees),
    # *s*aturation (0 <= s <= 100, percents), and *l*ightness
    # (0 <= l <= 100, percents).
    def self.hsl(h, s, l) : Color
      h = h.to_big_i
      s = s.to_big_i
      l = l.to_big_i

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

      rgb(
        r: Decimal.new(((rp.not_nil! + m) * 255).round),
        g: Decimal.new(((gp.not_nil! + m) * 255).round),
        b: Decimal.new(((bp.not_nil! + m) * 255).round),
      )
    end

    # Creates a `Color` from *h*ue (0 <= h <= 360, degrees),
    # *s*aturation (0 <= s <= 100, percents), and *v*alue
    # (0 <= v <= 100, percents).
    def self.hsv(h, s, v)
      h = h.to_big_i
      s = s.to_big_i
      v = v.to_big_i

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

      rgb(
        r: Decimal.new(((rp.not_nil! + m) * 255).round),
        g: Decimal.new(((gp.not_nil! + m) * 255).round),
        b: Decimal.new(((bp.not_nil! + m) * 255).round),
      )
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
