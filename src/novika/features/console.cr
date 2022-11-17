module Novika::Features
  # Enables the console API.
  #
  # Exposed vocabulary:
  #
  # * `console:on`, implemented by `on`
  # * `console:off`, implemented by `off`
  # * `console:256`, implemented by `colors_256`
  # * `console:compat`, implemented by `colors_compat`
  # * `console:truecolor`, implemented by `colors_truecolor`
  # * `console:peek`, implemented by `peek`
  # * `console:size`, implemented by `size`
  # * `console:hadKeyPressed?`, implemented by `had_key_pressed?`
  # * `console:hadCtrlPressed?`, implemented by `had_ctrl_pressed?`
  # * `console:hadAltPressed?`, implemented by `had_alt_pressed?`
  # * `console:hadShiftPressed?`, implemented by `had_shift_pressed?`
  # * `console:hadBackspacePressed?`, implemented by `had_backspace_pressed?`
  # * `console:hadFnPressed?`, implemented by `had_fn_pressed?`
  # * `console:hadInsertPressed?`, implemented by `had_insert_pressed?`
  # * `console:hadDeletePressed?`, implemented by `had_delete_pressed?`
  # * `console:hadHomePressed?`, implemented by `had_home_pressed?`
  # * `console:hadEndPressed?`, implemented by `had_end_pressed?`
  # * `console:hadPgupPressed?`, implemented by `had_pgup_pressed?`
  # * `console:hadPgdnPressed?`, implemented by `had_pgdn_pressed?`
  # * `console:hadLeftPressed?`, implemented by `had_left_pressed?`
  # * `console:hadRightPressed?`, implemented by `had_right_pressed?`
  # * `console:hadUpPressed?`, implemented by `had_up_pressed?`
  # * `console:hadDownPressed?`, implemented by `had_down_pressed?`
  # * `console:getCharPressed`, implemented by `get_char_pressed`
  # * `console:appendEcho`, implemented by `append_echo`
  # * `console:present`, implemented by `present`
  # * `console:clear`, implemented by `clear`
  abstract class IConsole
    include Feature

    # Foreground color used when there is no user-provided
    # foreground color.
    FG_DEFAULT = Color.new(Decimal.new(255), Decimal.new(255), Decimal.new(255))

    # Background color used when there is no user-provided
    # background color.
    BG_DEFAULT = Color.new(Decimal.new(0), Decimal.new(0), Decimal.new(0))

    def self.id : String
      "console"
    end

    def self.purpose : String
      "enables the console API"
    end

    def self.on_by_default? : Bool
      false
    end

    # Enables the Console API.
    abstract def on(engine)

    # Disables the Console API.
    abstract def off(engine)

    # Enables the 256-color output mode.
    abstract def colors_256(engine)

    # Enables the compatibility color (8-color) output mode.
    abstract def colors_compat(engine)

    # Enables the truecolor output mode.
    abstract def colors_truecolor(engine)

    # Returns the console width (in columns) and height (in rows).
    abstract def size(engine) : {Decimal, Decimal}

    # Peeks or waits for input. Refreshes the input state.
    #
    # * Negative *timeout* must wait indefinitely for input,
    #   and after receiving input refresh the state.
    #
    # * Zero *timeout* must refresh the input state without
    #   waiting for input.
    #
    # * Positive *timeout* must wait for input in a window
    #   *timeout* milliseconds long, and refresh the input
    #   state after receiving input.
    abstract def peek(engine, timeout : Decimal)

    # Returns boolean for whether any key was pressed.
    abstract def had_key_pressed?(engine) : Boolean

    # leaves Boolean for whether the CTRL key was pressed.
    abstract def had_ctrl_pressed?(engine) : Boolean

    # Returns boolean for whether the ALT key was pressed.
    abstract def had_alt_pressed?(engine) : Boolean

    # Returns boolean for whether the SHIFT key was pressed.
    abstract def had_shift_pressed?(engine) : Boolean

    # Returns boolean for whether the Backspace key
    # was pressed.
    abstract def had_backspace_pressed?(engine) : Boolean

    # Returns boolean for whether one of the function
    # keys F1-F12 was pressed.
    abstract def had_fn_pressed?(engine) : Boolean

    # Returns boolean for whether the INSERT key was pressed.
    abstract def had_insert_pressed?(engine) : Boolean

    # Returns boolean for whether the DELETE key was pressed.
    abstract def had_delete_pressed?(engine) : Boolean

    # Returns boolean for whether the HOME key was pressed.
    abstract def had_home_pressed?(engine) : Boolean

    # Returns boolean for whether the END key was pressed.
    abstract def had_end_pressed?(engine) : Boolean

    # Returns boolean for whether the PAGE UP key was pressed.
    abstract def had_pgup_pressed?(engine) : Boolean

    # Returns boolean for whether the PAGE DOWN key was pressed.
    abstract def had_pgdn_pressed?(engine) : Boolean

    # Returns boolean for whether the LEFT ARROW key
    # was pressed.
    abstract def had_left_pressed?(engine) : Boolean

    # Returns boolean for whether the RIGHT ARROW key
    # was pressed.
    abstract def had_right_pressed?(engine) : Boolean

    # Returns boolean for whether the UP ARROW key
    # was pressed.
    abstract def had_up_pressed?(engine) : Boolean

    # Returns boolean for whether the DOWN ARROW key
    # was pressed.
    abstract def had_down_pressed?(engine) : Boolean

    # Leaves char quote for the key that was pressed.
    # Usually a lowercase or uppercase letter; but also may
    # look like `'\\n'` or `'\\t'`, etc.)
    #
    # In case the key that was pressed cannot be represented
    # by the means of a quote, or if the user did not press
    # any key, an empty quote is left in place of Char
    # quote.
    abstract def get_char_pressed(engine) : Quote

    # Appends echo of *quote* colorized with *fg* and *bg*
    # colors at the given *x* and *y* position (in columns,
    # rows).
    abstract def append_echo(engine, x : Decimal, y : Decimal, fg : Color, bg : Color, quote : Quote)

    # Syncs the internal buffer with console.
    abstract def present(engine)

    # Clears the console with *fg* and *bg* colors.
    abstract def clear(engine, fg : Color, bg : Color)

    @timeout = Decimal.new(-1)

    # Returns the active primary foreground color.
    def fg
      bundle.fetch(IInk, &.fg.last?) || FG_DEFAULT
    end

    # Returns the active primary background color.
    def bg
      bundle.fetch(IInk, &.bg.last?) || BG_DEFAULT
    end

    def inject(into target)
      target.at("console:on", <<-END
      ( -- ): enables the console. Must be called before using
       any other console-related word.
      END
      ) { |engine| on(engine) }

      target.at("console:off", <<-END
      ( -- ): disables the console. Must be called at the end
       of your program or when you don't need console anymore.
      END
      ) { |engine| off(engine) }

      target.at("console:compat", <<-END
      ( -- ): enables the compatibility color output mode. In
       this mode, only 8 colors are available. All RGB colors
       are automatically reduced to one of those 8 colors.
      END
      ) { |engine| colors_compat(engine) }

      target.at("console:256", <<-END
      ( -- ): enables the 256-color output mode. In this mode,
       256 colors are available. All RGB colors are automatically
       reduced to one of those 256 colors.
      END
      ) { |engine| colors_256(engine) }

      target.at("console:truecolor", <<-END
      ( -- ): enables the truecolor output mode. In this mode,
      all colors are available and are passed to the console
      as-is.
      END
      ) { |engine| colors_truecolor(engine) }

      target.at("console:size", <<-END
      ( -- Cw Ch ): leaves the Console width (in columns) and
       Console height (in rows).
      END
      ) do |engine, stack|
        w, h = size(engine)
        w.onto(stack)
        h.onto(stack)
      end

      target.at("console:setTimeout", <<-END
      ( D -- ): sets input timeout to Duration, given in *milliseconds*.

       * If Duration is negative, `console:peek` will wait for
         input indefinitely (i.e., until there is input).

       * If Duration is zero, `console:peek` won't wait for input
         at all, but make note if there is any at the moment.

       * If Duration is positive, `console:peek` will peek during
         the timeout window.
      END
      ) do |_, stack|
        @timeout = stack.drop.a(Decimal)
      end

      target.at("console:peek", <<-END
      ( -- ): peeks or waits for input. See `console:setTimeout`.
       Refreshes the input state. Use `console:hadKeyPressed` and
       friends to explore the input state afterwards.
      END
      ) { |engine| peek(engine, @timeout) }

      target.at("console:hadKeyPressed?", <<-END
      ( -- B ): leaves Boolean for whether any key was pressed.
      END
      ) { |engine, stack| had_key_pressed?(engine).onto(stack) }

      target.at("console:hadCtrlPressed?", <<-END
      ( -- B ): leaves Boolean for whether the CTRL key was pressed.
      END
      ) { |engine, stack| had_ctrl_pressed?(engine).onto(stack) }

      target.at("console:hadAltPressed?", <<-END
      ( -- B ): leaves Boolean for whether the ALT key was pressed.
      END
      ) { |engine, stack| had_alt_pressed?(engine).onto(stack) }

      target.at("console:hadShiftPressed?", <<-END
      ( -- B ): leaves Boolean for whether the SHIFT key was pressed.
      END
      ) { |engine, stack| had_shift_pressed?(engine).onto(stack) }

      target.at("console:hadBackspacePressed?", <<-END
      ( -- B ): leaves Boolean for whether the Backspace key
       was pressed.
      END
      ) { |engine, stack| had_backspace_pressed?(engine).onto(stack) }

      target.at("console:hadFnPressed?", <<-END
      ( -- B ): leaves Boolean for whether one of the function
       keys F1-F12 was pressed.
      END
      ) { |engine, stack| had_fn_pressed?(engine).onto(stack) }

      target.at("console:hadInsertPressed?", <<-END
      ( -- B ): leaves Boolean for whether the INSERT key was pressed.
      END
      ) { |engine, stack| had_insert_pressed?(engine).onto(stack) }

      target.at("console:hadDeletePressed?", <<-END
      ( -- B ): leaves Boolean for whether the DELETE key was pressed.
      END
      ) { |engine, stack| had_delete_pressed?(engine).onto(stack) }

      target.at("console:hadHomePressed?", <<-END
      ( -- B ): leaves Boolean for whether the HOME key was pressed.
      END
      ) { |engine, stack| had_home_pressed?(engine).onto(stack) }

      target.at("console:hadEndPressed?", <<-DOC
      ( -- B ): leaves Boolean for whether the END key was pressed.
      DOC
      ) { |engine, stack| had_end_pressed?(engine).onto(stack) }

      target.at("console:hadPageUpPressed?", <<-END
      ( -- B ): leaves Boolean for whether the PAGE UP key was pressed.
      END
      ) { |engine, stack| had_pgup_pressed?(engine).onto(stack) }

      target.at("console:hadPageDownPressed?", <<-END
      ( -- B ): leaves Boolean for whether the PAGE DOWN key was pressed.
      END
      ) { |engine, stack| had_pgdn_pressed?(engine).onto(stack) }

      target.at("console:hadLeftPressed?", <<-END
      ( -- B ): leaves Boolean for whether the LEFT ARROW key
       was pressed.
      END
      ) { |engine, stack| had_left_pressed?(engine).onto(stack) }

      target.at("console:hadRightPressed?", <<-END
      ( -- B ): leaves Boolean for whether the RIGHT ARROW key
       was pressed.
      END
      ) { |engine, stack| had_right_pressed?(engine).onto(stack) }

      target.at("console:hadUpPressed?", <<-END
      ( -- B ): leaves Boolean for whether the UP ARROW key
       was pressed.
      END
      ) { |engine, stack| had_up_pressed?(engine).onto(stack) }

      target.at("console:hadDownPressed?", <<-END
      ( -- B ): leaves Boolean for whether the DOWN ARROW key
       was pressed.
      END
      ) { |engine, stack| had_down_pressed?(engine).onto(stack) }

      target.at("console:getCharPressed", <<-END
      ( -- Cq ): leaves Char quote for the key that was pressed.
       Usually a lowercase or uppercase letter; but also may look
       like `'\\n'` or `'\\t'`, etc.)

      In case the key that was pressed cannot be represented
      by the means of a quote, or if the user did not press
      any key, an empty quote is left in place of Char quote.
      END
      ) { |engine, stack| get_char_pressed(engine).onto(stack) }

      target.at("console:appendEcho", <<-END
      ( F X Y -- ): appends echo of Form at an X and Y position
       (in columns and rows correspondingly) using the foreground,
       background colors set by ink's `withEchoFg` and `withEchoBg`.
      END
      ) do |engine, stack|
        y = stack.drop.a(Decimal)
        x = stack.drop.a(Decimal)
        q = stack.drop.to_quote
        append_echo(engine, x, y, fg, bg, q)
      end

      target.at("console:withReverseAppendEcho", <<-END
      ( F X Y -- ): appends Form with foreground and background
       colors swapped with each other (background color is set
       to foreground color, and vice versa).
      END
      ) do |engine, stack|
        y = stack.drop.a(Decimal)
        x = stack.drop.a(Decimal)
        q = stack.drop.to_quote
        append_echo(engine, x, y, bg, fg, q)
      end

      target.at("console:present", "( -- ): syncs internal buffer and console.") do |engine|
        present(engine)
      end

      target.at("console:clear", "( -- ): clears console with primary colors.") do |engine|
        clear(engine, fg, bg)
      end
    end
  end
end
