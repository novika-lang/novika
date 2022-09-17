{% skip_file unless flag?(:novika_console) %}

require "termbox2"

module Novika::Features::Impl
  class Console < IConsole
    private M8_A   = Termbox::Color::M8_COLORS.map { |rgb| Color.rgb(*rgb) }.to_a
    private M256_A = Termbox::Color::M256_COLORS.map { |rgb| Color.rgb(*rgb) }.to_a

    @event : Termbox::BaseEvent?
    @palette : Array(Color)?

    def on(engine)
      Termbox.enable
    end

    def off(engine)
      Termbox.disable
    end

    def colors_256(engine)
      @palette = M256_A
      Termbox.set_output_mode(Termbox::OutputMode::M256)
    end

    def colors_compat(engine)
      @palette = M8_A
      Termbox.set_output_mode(Termbox::OutputMode::Normal)
    end

    def colors_truecolor(engine)
      @palette = nil
      Termbox.set_output_mode(Termbox::OutputMode::Truecolor)
    end

    def width(engine) : Decimal
      Decimal.new(Termbox.width)
    end

    def height(engine) : Decimal
      Decimal.new(Termbox.height)
    end

    def peek(engine, timeout : Decimal)
      @event = Termbox.peek?(timeout.to_i)
    end

    def had_key_pressed?(engine) : Boolean
      Boolean[!!@event.try &.is_a?(Termbox::Event::KeyEvent)]
    end

    def is_key_char?(engine, key : Quote) : Boolean
      Boolean[!Termbox::Key.parse?(key.string)]
    end

    def get_key_pressed!(engine) : Quote
      event = @event.as(Termbox::Event::KeyEvent)
      Quote.new((event.key || event.char || raise "unreachable").to_s)
    end

    private def to_tb_color(color)
      Termbox::Color.new(*(@palette ? color.closest(@palette.not_nil!) : color).rgb.map(&.to_i))
    end

    def print(engine, x : Decimal, y : Decimal, fg : Color, bg : Color, quote : Quote)
      fg, bg = to_tb_color(fg), to_tb_color(bg)
      Termbox.print(x.to_i, y.to_i, fg, bg, quote.string)
    end

    def present(engine)
      Termbox.present
    end

    def clear(engine, fg : Color, bg : Color)
      fg, bg = to_tb_color(fg), to_tb_color(bg)
      Termbox.clear(fg, bg) # Idk how efficient is this...
      Termbox.clear
    end
  end
end
