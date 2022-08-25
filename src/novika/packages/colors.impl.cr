require "colorize"

module Novika::Packages::Impl
  class Colors < IColors
    # Ensures decimals *r*, *g*, *b* are in 0-255 range, and
    # returns the three corresponding UInt8-s.
    private def color_u8(r : Decimal, g : Decimal, b : Decimal) : {UInt8, UInt8, UInt8}
      ri = r.to_i
      gi = g.to_i
      bi = b.to_i

      r.die("R channel must be 0-255, got: #{ri}") unless ri.in?(0..255)
      g.die("G channel must be 0-255, got: #{gi}") unless gi.in?(0..255)
      b.die("B channel must be 0-255, got: #{gi}") unless bi.in?(0..255)

      {ri.to_u8, gi.to_u8, bi.to_u8}
    end

    def with_color_echo(engine, fg : Color?, bg : Color?, form : Form)
      string = form.enquote(engine).string

      colorful = string.colorize
      colorful = colorful.fore(*color_u8(*fg)) if fg
      colorful = colorful.back(*color_u8(*bg)) if bg

      puts colorful
    end
  end
end
