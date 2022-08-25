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

    # TODO: remove when common color object exists
    alias Color = {Decimal, Decimal, Decimal}

    # Echo foreground color stack.
    property fg = [] of Color

    # Echo background color stack.
    property bg = [] of Color

    # Holds whether printing with colors is enabled (and desired).
    property? enabled : Bool do
      STDOUT.tty? && STDERR.tty? && ENV["TERM"]? != "dumb" && !ENV.has_key?("NO_COLOR")
    end

    # Echoes *form* with *fg* foreground color (if any) and
    # *bg* background color (if any). One of them is guaranteed
    # to be non-nil.
    abstract def with_color_echo(engine, fg : Color?, bg : Color?, form : Form)

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
        fg << {r, g, b}
      end

      target.at("withEchoBg", <<-END
      ( R G B -- ): pushes 0-255 Red, Green, Blue background color
       onto the echo background color stack.
      END
      ) do |engine|
        b = engine.stack.drop.assert(engine, Decimal)
        g = engine.stack.drop.assert(engine, Decimal)
        r = engine.stack.drop.assert(engine, Decimal)
        bg << {r, g, b}
      end

      target.at("dropEchoFg", <<-END
      ( -- ): drops a color from the echo foreground color stack.
      END
      ) { |engine| fg.pop? }

      target.at("dropEchoFg", <<-END
      ( -- ): drops a color from the echo background color stack.
      END
      ) { |engine| bg.pop? }

      target.at("withColorEcho", <<-END
      ( F -- ): echoes Form with last color from the echo foreground
       color stack set as foreground color, and the last as color from
       the echo background stack set as background color.
      END
      ) do |engine|
        form = engine.stack.drop
        if enabled? && (fg.last? || bg.last?)
          # If color output is enabled and either foreground
          # or background is set, use the color output method.
          with_color_echo(engine, fg.last?, bg.last?, form)
        else
          # Otherwise, TODO: invoke Essential#echo.
          puts form.enquote(engine).string
        end
      end
    end
  end
end
