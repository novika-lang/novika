{% skip_file unless flag?(:novika_console) %}

# require "termbox2" # TODO: uncomment when common Color object exists

module Novika::Packages::Impl
  class Console < IConsole
    private property event : Termbox::BaseEvent?

    def on(engine)
      Termbox.enable
    end

    def off(engine)
      Termbox.disable
    end

    def colors_256(engine)
      Termbox.set_output_mode(Termbox::OutputMode::M256)
    end

    def colors_compat(engine)
      Termbox.set_output_mode(Termbox::OutputMode::Normal)
    end

    def colors_truecolor(engine)
      Termbox.set_output_mode(Termbox::OutputMode::Truecolor)
    end

    def width(engine) : Decimal
      Decimal.new(Termbox.width)
    end

    def height(engine) : Decimal
      Decimal.new(Termbox.height)
    end

    def peek(engine, timeout : Decimal)
      self.event = Termbox.peek?(timeout.to_i)
    end

    def had_key_pressed?(engine) : Boolean
      Boolean[!!event.try &.is_a?(Termbox::Event::KeyEvent)]
    end

    def is_key_char?(engine, key : Quote) : Boolean
      Boolean[!Termbox::Key.parse?(key.string)]
    end

    def get_key_pressed!(engine) : Quote
      event = self.event.as(Termbox::Event::KeyEvent)
      Quote.new((event.key || event.char || raise "unreachable").to_s)
    end

    def print(engine, x : Decimal, y : Decimal, fg : Color, bg : Color, quote : Quote)
      Termbox.print(x.to_i, y.to_i, fg, bg, quote.string)
    end

    def present(engine)
      Termbox.present
    end

    def clear(engine, fg : Color, bg : Color)
      Termbox.clear(fg, bg) # Idk how efficient is this...
      Termbox.clear
    end
  end
end
