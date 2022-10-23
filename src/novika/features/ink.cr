module Novika::Features
  # Enables colorful output using `withColorAppendEcho` and friends.
  #
  # Exposed vocabulary:
  #
  # * `withEchoFg`, generic implementation
  # * `withEchoBg`, generic implementation
  # * `dropEchoFg`, generic implementation
  # * `dropEchoBg`, generic implementation
  # * `withColorAppendEcho`, implemented by `with_color_append_echo`
  # * `withEmphasisAppendEcho`, implemented by `with_emphasis_append_echo`
  # * `withReverseAppendEcho`, generic implementation; when no
  #   colors given by the use, `with_reverse_append_echo` is used.
  abstract class IInk
    include Feature

    NO_SYSTEM_ECHO_ERROR = "with...Echo words need 'echo' from feature system, " \
                           "but no instance of feature system was found"

    def self.id : String
      "ink"
    end

    def self.purpose : String
      "enables colorful output using 'withColorAppendEcho' and friends"
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

    # Appends *form* with foreground and background colors swapped
    # with each other.
    abstract def with_emphasis_append_echo(engine, form : Form)

    # Appends *form* with inverse style (background color is
    # set to foreground color, and vice versa).
    #
    # Note: if both foreground and background colors are set
    # by the user, `with_color_append_echo` is preferred over
    # this method.
    abstract def with_reverse_append_echo(engine, form : Form)

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

      target.at("withReverseAppendEcho", <<-END
      ( F -- ): appends Form with foreground and background
       colors swapped with each other (background color is set
       to foreground color, and vice versa).

      Note: if unsupported by the output stream, will print
      Form as-is.
      END
      ) do |engine, stack|
        form = stack.drop
        if enabled? && (fg.last? && bg.last?)
          with_color_append_echo(engine, bg.last, fg.last, form)
        else
          with_reverse_append_echo(engine, form)
        end
      end

      target.at("withEmphasisAppendEcho", <<-END
      ( F -- ): appends emphasized echo of Form. Typically bold
       style is used for emphasis, italic is allowed as well.
      END
      ) do |engine, stack|
        form = stack.drop
        if enabled?
          with_emphasis_append_echo(engine, form)
        elsif system = bundle[ISystem]?
          system.append_echo(engine, form)
        else
          form.die(NO_SYSTEM_ECHO_ERROR)
        end
      end

      target.at("withColorAppendEcho", <<-END
      ( F -- ): appends Form with last color from the echo
       foreground color stack set as foreground color, and
       the last as color from the echo background stack set
       as background color, to the standard output stream.

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
