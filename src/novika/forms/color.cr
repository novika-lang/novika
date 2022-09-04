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

    # Returns a tuple with H, S, L of this color.
    def hsl : {Decimal, Decimal, Decimal}
      r = self.r.to_f64
      g = self.g.to_f64
      b = self.b.to_f64

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

    # Returns a tuple with H, S, V of this color.
    def hsv : {Decimal, Decimal, Decimal}
      r = self.r.to_f64
      g = self.g.to_f64
      b = self.b.to_f64

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

    # Returns a tuple with L, C, H of this color.
    def lch : {Decimal, Decimal, Decimal}
      l, c, h = Color.rgb2lch(r.to_f64, g.to_f64, b.to_f64)
      {Decimal.new(l),
       Decimal.new(c),
       Decimal.new(h)}
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

    # Creates a `Color` from RGB.
    def self.rgb(r, g, b) : Color
      new(r, g, b)
    end

    # Creates a `Color` from *h*ue (0 <= h <= 360, degrees),
    # *s*aturation (0 <= s <= 100, percents), and *l*ightness
    # (0 <= l <= 100, percents).
    def self.hsl(h, s, l) : Color
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

      rgb(
        r: Decimal.new(((rp.not_nil! + m) * 255).round),
        g: Decimal.new(((gp.not_nil! + m) * 255).round),
        b: Decimal.new(((bp.not_nil! + m) * 255).round),
      )
    end

    # Creates a `Color` from *l*ightness (0-100), *c*hroma
    # (0-132), *h*ue (0-360).
    def self.lch(l, c, h)
      l = l.to_f64
      c = c.to_f64
      h = h.to_f64
      r, g, b = lch2rgb(l, c, h)
      new(Decimal.new(r), Decimal.new(g), Decimal.new(b))
    end

    # Implementation (pretty much) copy-pasted from
    #
    # https://github.com/gka/chroma.js

    # D65 standard referent

    private D65_X = 0.950470
    private D65_Y =        1
    private D65_Z = 1.088830

    private LAB_T0 = 4 / 29
    private LAB_T1 = 6 / 29
    private LAB_T2 = 3 * LAB_T1 ** 2
    private LAB_T3 = LAB_T1 ** 3

    # --- LCH -> RGB ---------------------------------------

    private def self.lab_xyz(t)
      t > LAB_T1 ? t * t * t : LAB_T2 * (t - LAB_T0)
    end

    private def self.xyz_rgb(n)
      (255 * (n <= 0.00304 ? 12.92 * n : 1.055 * n**(1 / 2.4) - 0.055)).round.clamp(0..255)
    end

    private def self.lab2rgb(l, a, b)
      y = (l + 16) / 116
      x = y + a / 500
      z = y - b / 200

      y = D65_Y * lab_xyz(y)
      x = D65_X * lab_xyz(x)
      z = D65_Z * lab_xyz(z)

      r = xyz_rgb(3.2404542 * x - 1.5371385 * y - 0.4985314 * z) # D65 -> sRGB
      g = xyz_rgb(-0.9692660 * x + 1.8760108 * y + 0.0415560 * z)
      b = xyz_rgb(0.0556434 * x - 0.2040259 * y + 1.0572252 * z)

      {r, g, b}
    end

    private def self.lch2lab(l, c, h)
      h = h * Math::PI / 180
      {l, Math.cos(h) * c, Math.sin(h) * c}
    end

    protected def self.lch2rgb(l, c, h)
      lab2rgb *lch2lab(l, c, h)
    end

    # --- RGB -> LCH ---------------------------------------

    private def self.lab2lch(l, a, b)
      c = Math.sqrt(a ** 2 + b ** 2)
      h = (Math.atan2(b, a) * 180 / Math::PI + 360) % 360
      {l, c, h}
    end

    private def self.rgb_xyz(n)
      (n /= 255) <= 0.04045 ? n / 12.92 : ((n + 0.055) / 1.055)**2.4
    end

    private def self.xyz_lab(t)
      t > LAB_T3 ? Math.cbrt(t) : t / LAB_T2 + LAB_T0
    end

    private def self.rgb2xyz(r, g, b)
      r = rgb_xyz(r)
      g = rgb_xyz(g)
      b = rgb_xyz(b)

      x = xyz_lab((0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / D65_X)
      y = xyz_lab((0.2126729 * r + 0.7151522 * g + 0.0721750 * b) / D65_Y)
      z = xyz_lab((0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / D65_Z)

      {x, y, z}
    end

    private def self.rgb2lab(r, g, b)
      x, y, z = rgb2xyz(r, g, b)
      l = 116 * y - 16
      {l < 0 ? 0 : l, 500 * (x - y), 200 * (y - z)}
    end

    protected def self.rgb2lch(r, g, b)
      l, a, b = lab2lch *rgb2lab(r, g, b)
      {l.round,
       a.round,
       b.round}
    end
  end
end
