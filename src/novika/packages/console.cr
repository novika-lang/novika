{% skip_file unless flag?(:novika_console) %}

# TODO: ^^^^ Maybe tell the user their platform isn't supported,
# or have an alternative windows implementation.

require "termbox2" # TODO: remove when common color object exists

struct Termbox::Color # TODO: remove when common color object exists
  include Novika::Form

  def self.typedesc
    "color"
  end
end

# TODO: use same color as in Colors
#
# TODO: refactor the API, it's horrible for portability and
# general usability and exists to exist only
#
# NOTE: there should probably be a bunch of Pallettes as well.
# If you give a color to a Palette, it will return you the
# (closest) matching color it knows. This will sort of make
# console:compat & friends portable, because now resolution is
# all on the Novika side, and the goal of the renderer/color user
# is to resolve the color via its own Palette.
#
# Now Novika could have Color as a form (because we're living
# in the 21st century). It already does for Console, but it's
# more of a hack than a feature.

# TODO: don't pass engine as argument. Make it an ivar smhw
# (probably by attaching packages to engines instead of to
# nothing in particular).

module Novika::Packages
  # Enables the console API.
  #
  # Exposed vocabulary:
  #
  # * `console:on`, implemented by `on`
  # * `console:off`, implemented by `off`
  # * `console:256`, implemented by `colors_256`
  # * `console:compat`, implemented by `colors_compat`
  # * `console:truecolor`, implemented by `colors_truecolor`
  # * `console:color`, generic implementation
  # * `console:width`, implemented by `width`
  # * `console:height`, implemented by `height`
  # * `console:peek`, implemented by `peek`
  # * `console:hadKeyPressed`, implemented by `had_key_pressed?`
  # * `console:isKeyChar`, implemented by `is_key_char?`
  # * `console:getKeyPressed`, implemented by `get_key_pressed!`
  # * `console:print`, implemented by `print`
  # * `console:present`, implemented by `present`
  # * `console:clear`, implemented by `clear`
  # * `console:setPrimary`, implemented as setting `fg` and `bg`
  abstract class IConsole
    include Package

    def self.id : String
      "console"
    end

    def self.purpose : String
      "enables the console API"
    end

    def self.on_by_default? : Bool
      false
    end

    # TODO: remove when common color object exists
    alias Color = Termbox::Color

    # Enables the Console API.
    abstract def on(engine)

    # Disables the Console API.
    abstract def off(engine)

    # Enables the 256-color output mode.
    abstract def colors_256(engine)

    # Enables the compatibility color output mode.
    abstract def colors_compat(engine)

    # Enables the truecolor output mode.
    abstract def colors_truecolor(engine)

    # Returns the console width (in columns).
    abstract def width(engine) : Decimal

    # Returns the console height (in rows).
    abstract def height(engine) : Decimal

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

    # Returns a boolean for whether there was a key press
    # event registered.
    abstract def had_key_pressed?(engine) : Boolean

    # Returns whether *key* quote is considered a single-
    # character key.
    abstract def is_key_char?(engine, key : Quote) : Boolean

    # Returns the name of the key that was pressed. May be
    # unsafe for Novika-land: `had_key_pressed?` must be
    # checked beforehand.
    abstract def get_key_pressed!(engine) : Quote

    # Prints *quote* colorized with *fg* and *bg* colors at
    # the given *x* and *y* position (in columns, rows).
    abstract def print(engine, x : Decimal, y : Decimal, fg : Color, bg : Color, quote : Quote)

    # Syncs the internal buffer with console.
    abstract def present(engine)

    # Clears the console with *fg* and *bg* colors.
    abstract def clear(engine, fg : Color, bg : Color)

    # Holds the active primary foreground color.
    property fg = Color::White

    # Holds the active primary background color.
    property bg = Color::Black

    @timeout = Decimal.new(-1)

    def inject(into target)
      target.at("console:on", "( -- ): enables the Console API.") { |engine| on(engine) }
      target.at("console:off", "( -- ): disables the Console API.") { |engine| off(engine) }

      target.at("console:compat", <<-END
      ( -- ): enables the compatibility color output mode. In
       this mode, only 8 colors are available. All RGB colors
       are automatically reduced to one of those 8 colors.
      END
      ) { |engine| colors_compat(engine) }
      # TODO: self.palette = MyOwnCustomAwesome8ColorPalette.new

      target.at("console:256", <<-END
      ( -- ): enables the 256-color output mode. In this mode,
       256 colors are available. All RGB colors are automatically
       reduced to one of those 256 colors.
      END
      ) { |engine| colors_256(engine) }
      # TODO: self.palette = MyOwnCustomAwesome256ColorPalette.new

      target.at("console:truecolor", <<-END
      ( -- ): enables the truecolor output mode. In this mode,
      all colors are available and are passed to the console
      as-is.
      END
      ) { |engine| colors_truecolor(engine) }
      # TODO: self.palette = MyOwnCustomAwesomeNoopColorPalette.new
      #                      ^^^ which all of the above probably should inherit

      # our custom color object should support color:rgb, color:hsl,
      # maybe just maybe if I can get this right at some point color:lch
      target.at("console:color", <<-END
      ( Rd Gd Bd -- C ): creates an RGB Color from the three
       decimals: R for the Red channel value (0-255), G for
       the Green channel value (0-255), and B for the blue
       channel value (0-255).
      END
      ) do |engine|
        # TODO: Here that "same as in Colors" color object
        # should be created. No need to make this abstract.
        #
        # color_u8 would be handy, should be reused, but see
        # the below & above TODO.
        b = engine.stack.drop.assert(engine, Decimal)
        g = engine.stack.drop.assert(engine, Decimal)
        r = engine.stack.drop.assert(engine, Decimal)
        Color[r.to_i, g.to_i, b.to_i].push(engine)
      end

      # TODO: This one should work the same as in Colors, where
      # we have withEchoFg and withEchoBg that push onto a
      # color stack. Probably could extract that into a module
      # and reuse here.
      target.at("console:setPrimary", <<-END
      ( Fc Bc -- ): set the primary Foreground and Background colors.
       Before you `console:clear`, only `console:print` will respect
       these colors. But after you `console:clear`, the whole console
       will be cleared with these colors.
      END
      ) do |engine|
        self.bg = engine.stack.drop.assert(engine, Color)
        self.fg = engine.stack.drop.assert(engine, Color)
      end

      target.at("console:width", "( -- W ): leaves console width (in columns)") do |engine|
        width(engine).push(engine)
      end

      target.at("console:height", "( -- W ): leaves console height (in rows)") do |engine|
        height(engine).push(engine)
      end

      target.at("console:setTimeout", <<-END
      ( Tms -- ): sets input Timeout to the given amount of milliseconds.

       * If Timeout is negative, `console:peek` will wait for
         input indefinitely (i.e., until there is input).

       * If Timeout is zero, `console:peek` won't wait for input
         at all, but make note if there is any at the moment.

       * If Timeout is positive, `console:peek` will peek
         during the timeout window.
      END
      ) do |engine|
        @timeout = engine.stack.drop.assert(engine, Decimal)
      end

      target.at("console:peek", <<-END
      ( -- ): peeks or waits for input. See `console:setTimeout`. Refreshes
       the input state. Use `console:hadKeyPressed` and friends to explore
       the input state afterwards.
      END
      ) { |engine| peek(engine, @timeout) }

      # TODO: instead of this, have
      #
      #  * hadCtrlPressed (if possible, fallback false)
      #  * hadAltPressed  (if possible, fallback false)
      #  * hadCharPressed (the letters)
      #  * hadTabPressed
      #  * ...etc...
      #
      # This makes portability a bit easier and I won't have
      # to translate the enormous Termbox struct and whatnot
      # again...
      target.at("console:hadKeyPressed", <<-END
      ( -- B ): leaves Boolean for whether there was a key press
       event registered. To get the name of the key that was pressed,
       use `console:getKeyPressed`, *but only after making sure
       that Boolean is true*.
      END
      ) { |engine| had_key_pressed?(engine).push(engine) }

      target.at("console:getKeyPressed", <<-END
      ( -- Kq ): leaves most recent key pressed. Dies if none. You
       can use `console:hadKeyPressed` to check whether there was
       a key pressed before opening this word.
      END
      ) do |engine|
        unless had_key_pressed?(engine)
          raise Died.new("no key pressed: make sure to check `console:hadKeyPressed` first")
        end
        get_key_pressed!(engine).push(engine)
      end

      # TODO: this should be removed, this is a hack to get
      # things to work. See TODO over `console:hadKeyPressed`

      target.at("console:isKeyChar", <<-END
      ( Kq -- B ): leaves Boolean for whether Key quote is
       considered a single-character key.
      END
      ) do |engine|
        key = engine.stack.drop.assert(engine, Quote)

        is_key_char?(engine, key).push(engine)
      end

      # this should be console:echo I guess...
      #
      # and it should use the color stack...

      target.at("console:print", <<-END
      ( Q X Y -- ): prints Quote using the foreground, background
       colors set by `console:setPrimary`, at an X and Y position
       (in columns and rows correspondingly).
      END
      ) do |engine|
        y = engine.stack.drop.assert(engine, Decimal)
        x = engine.stack.drop.assert(engine, Decimal)
        q = engine.stack.drop.assert(engine, Quote)
        print(engine, x, y, fg, bg, q)
      end

      target.at("console:present", "( -- ): syncs internal buffer and console") do |engine|
        present(engine)
      end

      target.at("console:clear", "( -- ): clears console with primary colors") do |engine|
        clear(engine, fg, bg)
      end
    end
  end
end
