module Novika::Packages::Impl
  class Colors < IColors
    # Echo foreground color stack.
    property fg = [] of {UInt8, UInt8, UInt8}
    # Echo background color stack.
    property bg = [] of {UInt8, UInt8, UInt8}

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

    def with_echo_fg(engine, r : Decimal, g : Decimal, b : Decimal)
      fg << color_u8(r, g, b)
    end

    def with_echo_bg(engine, r : Decimal, g : Decimal, b : Decimal)
      bg << color_u8(r, g, b)
    end

    def drop_echo_fg(engine)
      fg.pop?
    end

    def drop_echo_bg(engine)
      bg.pop?
    end

    def with_color_echo(engine, form : Form)
      string = form.enquote(engine).string

      colorful = string.colorize
      colorful = colorful.fore(*fg.last) unless fg.empty?
      colorful = colorful.back(*bg.last) unless bg.empty?

      puts colorful
    end

    def without_color_echo(engine, form : Form)
      string = form.enquote(engine).string

      puts string
    end
  end
end
