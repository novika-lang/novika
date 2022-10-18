module Novika::Features
  # Enables colorful output using `withColorEcho` and friends.
  #
  # Exposed vocabulary:
  #
  # * `withEchoFg`, generic implementation
  # * `withEchoBg`, generic implementation
  # * `dropEchoFg`, generic implementation
  # * `dropEchoBg`, generic implementation
  # * `withColorEcho`, implemented by `with_color_echo`
  abstract class IInk
    include Feature

    NO_SYSTEM_ECHO_ERROR = "withColorEcho requires 'echo' from feature system, " \
                           "but no instance of feature system was found"

    def self.id : String
      "ink"
    end

    def self.purpose : String
      "enables colorful output using 'withColorEcho' and friends"
    end

    def self.on_by_default? : Bool
      true
    end

    # Echo foreground color stack.
    property fg = [] of Color

    # Echo background color stack.
    property bg = [] of Color

    # Holds whether printing with colors is enabled (and desired).
    #
    # Defaults to `Novika.colorful?`.
    property? enabled : Bool { Novika.colorful? }

    # Appends *form* with *fg* foreground color (if any) and
    # *bg* background color (if any) to the standard output
    # stream. One of *fg*, *bg* is guaranteed to be non-nil.
    abstract def with_color_append_echo(engine, fg : Color?, bg : Color?, form : Form)

    # Injects the colors vocabulary into *target*.
    def inject(into target)
      target.at("withEchoFg", <<-END
      ( C -- ): pushes Color form onto the echo foreground
       color stack.
      END
      ) do |_, stack|
        fg << stack.drop.a(Color)
      end

      target.at("withEchoBg", <<-END
      ( C -- ): pushes Color form onto the echo background
       color stack.
      END
      ) do |_, stack|
        bg << stack.drop.a(Color)
      end

      target.at("dropEchoFg", <<-END
      ( -- ): drops a color from the echo foreground color stack.
      END
      ) { fg.pop? }

      target.at("dropEchoFg", <<-END
      ( -- ): drops a color from the echo background color stack.
      END
      ) { bg.pop? }

      target.at("withColorAppendEcho", <<-END
      ( F -- ): appends Form with last color from the echo
       foreground color stack set as foreground color, and
       the last as color from the echo background stack set
       as background color, to the standard output stream.

      Requires the system feature, but it's on by default so you
      normally don't need to worry about this.

      Note: some implementations (particularly the Novika's default
      one) choose to snap foreground and background colors to
      system's basic 16 colors for compatibility & portability.
      If you want more cross-platform control over colors (and
      pretty much everything else), take a look at feature console.
      END
      ) do |engine, stack|
        form = stack.drop

        if enabled? && (fg.last? || bg.last?)
          # If color output is enabled and either foreground
          # or background is set, output with color.
          with_color_append_echo(engine, fg.last?, bg.last?, form)
        elsif system = bundle[ISystem]?
          # Use system echo as a fallback (colorless) echo.
          system.append_echo(engine, form)
        else
          # At least let the user know we tried. At this point
          # there really isn't anything to do other than die or
          # silently ignore.
          form.die(NO_SYSTEM_ECHO_ERROR)
        end
      end
    end
  end
end
