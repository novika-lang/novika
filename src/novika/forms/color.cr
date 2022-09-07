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
      l, c, h = Color.rgb2lch(r.to_f64, g.to_f64, b.to_f64)

      {Decimal.new(l), Decimal.new(c), Decimal.new(h)}
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

    private def self.xyz_srgb(n)
      n <= 0.00304 ? 12.92 * n : 1.055 * n**(1 / 2.4) - 0.055
    end

    private def self.lab2srgb(l, a, b)
      y = (l + 16) / 116
      x = y + a / 500
      z = y - b / 200

      y = D65_Y * lab_xyz(y)
      x = D65_X * lab_xyz(x)
      z = D65_Z * lab_xyz(z)

      r = xyz_srgb(3.2404542 * x - 1.5371385 * y - 0.4985314 * z) # D65 -> sRGB
      g = xyz_srgb(-0.9692660 * x + 1.8760108 * y + 0.0415560 * z)
      b = xyz_srgb(0.0556434 * x - 0.2040259 * y + 1.0572252 * z)

      {r, g, b}
    end

    private def self.lch2lab(l, c, h)
      h = h * Math::PI / 180
      {l, Math.cos(h) * c, Math.sin(h) * c}
    end

    private def self.lch2srgb_impl(l, c, h)
      lab2srgb *lch2lab(l, c, h)
    end

    # The two methods below are copied from tabatkins's commit
    # from:
    #
    # https://github.com/LeaVerou/css.land/pull/3/commits/d2ec6bdb80317358e2e2e5826b01e87130afd238
    #
    # I'm too dumb for all this math stuff so these are pretty
    # mach copy-pastes, just a bit crystalized.

    # Returns whether an *l*, *c*, *h* color is inside of the
    # sRGB gamut.
    private def self.lch_in_srgb?(l, c, h)
      ε = 0.000005
      r, g, b = lch2srgb_impl(l, c, h)
      r.in?(-ε..1 + ε) && g.in?(-ε..1 + ε) && b.in?(-ε..1 + ε)
    end

    private def self.force_into_srgb(l, c, h)
      return {l, c, h} if lch_in_srgb?(l, c, h)

      hi_c = c
      lo_c = 0
      c /= 2

      while hi_c - lo_c > 0.0001
        if lch_in_srgb?(l, c, h)
          lo_c = c
        else
          hi_c = c
        end
        c = (hi_c + lo_c)/2
      end

      {l, c, h}
    end

    # Returns an RGB tuple for the given LCH color.
    #
    # The color is forced into the sRGB gamut.
    protected def self.lch2rgb(l, c, h)
      r, g, b = lch2srgb_impl *force_into_srgb(l, c, h)
      {(255 * r).round,
       (255 * g).round,
       (255 * b).round}
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

    # Returns an LCH tuple for an RGB color.
    protected def self.rgb2lch(r, g, b)
      l, a, b = lab2lch *rgb2lab(r, g, b)
      {l.round,
       a.round,
       b.round}
    end
  end
end
