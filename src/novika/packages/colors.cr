require "colorize"

# Note: this should use the same color object as console, with
# same color space reduction as console does already. The only
# interface with Novika should be `r g b color` and `fg bg print`
# (or something like that), so that the only thing Console actually
# adds is the ability to choose an arbitrary position to move to.

module Novika::Packages
  # Enables colorful output using `withColorEcho` and friends.
  #
  # Exposed vocabulary:
  #
  # * `withEchoFg`, implemented by `with_echo_fg`
  # * `withEchoBg`, implemented by `with_echo_bg`
  # * `dropEchoFg`, implemented by `drop_echo_fg`
  # * `dropEchoBg`, implemented by `drop_echo_bg`
  # * `withColorEcho`, implemented by `with_color_echo`
  abstract class IColors
    include Package

    def self.id : String
      "colors"
    end

    def self.purpose : String
      "enables colorful output using 'withColorEcho' and friends"
    end

    def self.on_by_default? : Bool
      true
    end

    # Holds whether printing with colors is enabled (and desired).
    property? enabled : Bool do
      STDOUT.tty? && STDERR.tty? && ENV["TERM"]? != "dumb" && !ENV.has_key?("NO_COLOR")
    end

    # Pushes 0-255 *r*ed, *g*reen, *b*lue foreground color
    # onto the echo foreground color stack.
    abstract def with_echo_fg(engine, r : Decimal, g : Decimal, b : Decimal)

    # Pushes 0-255 *r*ed, *g*reen, *b*lue background color
    # onto the echo background color stack.
    abstract def with_echo_bg(engine, r : Decimal, g : Decimal, b : Decimal)

    # Drops a color from the echo foreground color stack.
    abstract def drop_echo_fg(engine)

    # Drops a color from the echo background color stack.
    abstract def drop_echo_bg(engine)

    # Echoes *form* with last color from the echo foreground color
    # stack set as foreground color, and the last as color from
    # the echo background stack set as background color.
    abstract def with_color_echo(engine, form : Form)

    # Fallback for echoing *form* when color is disabled
    # (or not desired).
    abstract def without_color_echo(engine, form : Form)

    # Injects the colors vocabulary into *target*.
    def inject(into target)
      target.at("withEchoFg", <<-END
      ( R G B -- ): pushes 0-255 Red, Green, Blue foreground color
       onto the echo foreground color stack.
      END
      ) do |engine|
        b = engine.stack.drop.assert(engine, Decimal)
        g = engine.stack.drop.assert(engine, Decimal)
        r = engine.stack.drop.assert(engine, Decimal)
        with_echo_fg(engine, r, g, b)
      end

      target.at("withEchoBg", <<-END
      ( R G B -- ): pushes 0-255 Red, Green, Blue background color
       onto the echo background color stack.
      END
      ) do |engine|
        b = engine.stack.drop.assert(engine, Decimal)
        g = engine.stack.drop.assert(engine, Decimal)
        r = engine.stack.drop.assert(engine, Decimal)
        with_echo_bg(engine, r, g, b)
      end

      target.at("dropEchoFg", <<-END
      ( -- ): drops a color from the echo foreground color stack.
      END
      ) { |engine| drop_echo_fg(engine) }

      target.at("dropEchoFg", <<-END
      ( -- ): drops a color from the echo background color stack.
      END
      ) { |engine| drop_echo_bg(engine) }

      target.at("withColorEcho", <<-END
      ( F -- ): echoes Form with last color from the echo foreground
       color stack set as foreground color, and the last as color from
       the echo background stack set as background color.
      END
      ) do |engine|
        # TODO reach IKernel#echo smhw
        form = engine.stack.drop
        enabled? ? with_color_echo(engine, form) : without_color_echo(engine, form)
      end
    end
  end
end
