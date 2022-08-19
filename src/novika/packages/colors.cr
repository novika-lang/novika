require "colorize"

# Note: this should use the same color object as console, with
# same color space reduction as console does already. The only
# interface with Novika should be `r g b color` and `fg bg print`
# (or something like that), so that the only thing Console actually
# adds is the ability to choose an arbitrary position to move to.

module Novika::Packages
  class Colors
    include Package

    def self.id
      "colors"
    end

    property fg = [] of {UInt8, UInt8, UInt8}
    property bg = [] of {UInt8, UInt8, UInt8}

    def initialize(@enabled = false)
    end

    private def color_u8(r : Decimal, g : Decimal, b : Decimal)
      ru = r.to_i
      gu = g.to_i
      bu = b.to_i

      r.die("R channel must be 0-255, got: #{ru}") unless ru.in?(0..255)
      g.die("G channel must be 0-255, got: #{gu}") unless gu.in?(0..255)
      b.die("B channel must be 0-255, got: #{bu}") unless bu.in?(0..255)

      {ru.to_u8, gu.to_u8, bu.to_u8}
    end

    def inject(into target)
      target.at("withEchoFg", <<-END
      ( R G B -- ): pushes 0-255 Red, Green, Blue foreground color
       to echo color stack.
      END
      ) do |engine|
        b = engine.stack.drop.assert(engine, Decimal)
        g = engine.stack.drop.assert(engine, Decimal)
        r = engine.stack.drop.assert(engine, Decimal)
        fg << color_u8(r, g, b)
      end

      target.at("withEchoBg", <<-END
      ( R G B -- ): pushes 0-255 Red, Green, Blue background color
       to echo color stack.
      END
      ) do |engine|
        b = engine.stack.drop.assert(engine, Decimal)
        g = engine.stack.drop.assert(engine, Decimal)
        r = engine.stack.drop.assert(engine, Decimal)
        bg << color_u8(r, g, b)
      end

      target.at("dropEchoFg", "( -- ): drops an echo foreground color") do
        fg.pop?
      end

      target.at("dropEchoBg", "( -- ): drops an echo background color") do
        bg.pop?
      end

      target.at("withColorEcho", <<-END
      ( F -- ): echoes Form with last color from the echo color stack.
      END
      ) do |engine|
        form = engine.stack.drop
        string = form.enquote(engine).string

        if @enabled
          string = string.colorize
          string = string.fore(*fg.last) unless fg.empty?
          string = string.back(*bg.last) unless bg.empty?
        end

        puts string
      end
    end
  end
end
