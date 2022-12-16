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

    def size(engine) : {Decimal, Decimal}
      {Decimal.new(Termbox.width), Decimal.new(Termbox.height)}
    end

    def read_key(engine, timeout : Decimal)
      @event = Termbox.peek?(timeout.to_i)
    end

    def had_key_pressed?(engine) : Boolean
      event = @event.as?(Termbox::Event::KeyEvent)

      Boolean[!!event]
    end

    def had_ctrl_pressed?(engine) : Boolean
      event = @event.as?(Termbox::Event::KeyEvent)

      Boolean[event && event.mod.ctrl?]
    end

    def had_alt_pressed?(engine) : Boolean
      event = @event.as?(Termbox::Event::KeyEvent)

      Boolean[event && event.mod.alt?]
    end

    def had_shift_pressed?(engine) : Boolean
      event = @event.as?(Termbox::Event::KeyEvent)

      Boolean[event && (event.char.try(&.uppercase?) || event.mod.shift?)]
    end

    def had_fn_pressed?(engine) : Boolean
      had_key_pressed? do |key|
        case key
        when .f1?, .f2?, .f3?,
             .f4?, .f5?, .f6?,
             .f7?, .f8?, .f9?,
             .f10?, .f11?, .f12?
          true
        end
      end
    end

    def had_backspace_pressed?(engine) : Boolean
      had_key_pressed? { |key| key.backspace? || key.backspace2? }
    end

    {% for key in %w(insert delete home end pgup pgdn) %}
      def had_{{key.id}}_pressed?(engine) : Boolean
        had_key_pressed? &.{{key.id}}?
      end
    {% end %}

    def had_left_pressed?(engine) : Boolean
      had_key_pressed? &.arrow_left?
    end

    def had_right_pressed?(engine) : Boolean
      had_key_pressed? &.arrow_right?
    end

    def had_up_pressed?(engine) : Boolean
      had_key_pressed? &.arrow_up?
    end

    def had_down_pressed?(engine) : Boolean
      had_key_pressed? &.arrow_down?
    end

    def had_char_pressed?(engine) : Boolean
      Boolean[!!@event.as?(Termbox::Event::KeyEvent).try &.char.try &.printable?]
    end

    def get_char_pressed(engine) : Quote
      unless event = @event.as?(Termbox::Event::KeyEvent)
        return Quote.new("")
      end

      if char = event.char
        return Quote.new(char)
      end

      # Key and char are mutually exclusive: if there is a
      # char, then there is no key, and vice versa.
      key = event.key.not_nil!

      case key
      when .ctrl_tilde?       then char = '~'
      when .ctrl_2?           then char = '2'
      when .ctrl_a?           then char = 'a'
      when .ctrl_b?           then char = 'b'
      when .ctrl_c?           then char = 'c'
      when .ctrl_d?           then char = 'd'
      when .ctrl_e?           then char = 'e'
      when .ctrl_f?           then char = 'f'
      when .ctrl_g?           then char = 'g'
      when .ctrl_h?           then char = 'h'
      when .tab?              then char = '\t'
      when .ctrl_i?           then char = 'i'
      when .ctrl_j?           then char = 'j'
      when .ctrl_k?           then char = 'k'
      when .ctrl_l?           then char = 'l'
      when .enter?            then char = '\n'
      when .ctrl_m?           then char = 'm'
      when .ctrl_n?           then char = 'n'
      when .ctrl_o?           then char = 'o'
      when .ctrl_p?           then char = 'p'
      when .ctrl_q?           then char = 'q'
      when .ctrl_r?           then char = 'r'
      when .ctrl_s?           then char = 's'
      when .ctrl_t?           then char = 't'
      when .ctrl_u?           then char = 'u'
      when .ctrl_v?           then char = 'v'
      when .ctrl_w?           then char = 'w'
      when .ctrl_x?           then char = 'x'
      when .ctrl_y?           then char = 'y'
      when .ctrl_z?           then char = 'z'
      when .esc?              then char = '\e'
      when .ctrl_lsq_bracket? then char = '['
      when .ctrl_3?           then char = '3'
      when .ctrl_4?           then char = '4'
      when .ctrl_backslash?   then char = '\\'
      when .ctrl_5?           then char = '5'
      when .ctrl_rsq_bracket? then char = ']'
      when .ctrl_6?           then char = '6'
      when .ctrl_7?           then char = '7'
      when .ctrl_slash?       then char = '/'
      when .ctrl_underscore?  then char = '_'
      when .space?            then char = ' '
      when .ctrl_8?           then char = '8'
      when .f1?               then char = '1'
      when .f2?               then char = '2'
      when .f3?               then char = '3'
      when .f4?               then char = '4'
      when .f5?               then char = '5'
      when .f6?               then char = '6'
      when .f7?               then char = '7'
      when .f8?               then char = '8'
      when .f9?               then char = '9'
      when .f10?              then char = "10"
      when .f11?              then char = "11"
      when .f12?              then char = "12"
      else
        return Quote.new("")
      end

      Quote.new(char)
    end

    private def had_key_pressed?
      event = @event.as?(Termbox::Event::KeyEvent)

      return Boolean[false] unless event
      return Boolean[false] unless key = event.key

      Boolean[!!yield key]
    end

    private def to_tb_color(color)
      Termbox::Color.new(*(@palette ? color.closest(@palette.not_nil!) : color).rgb.map(&.to_i))
    end

    def change(engine, x : Decimal, y : Decimal, fg : Color, bg : Color)
      fg, bg = to_tb_color(fg), to_tb_color(bg)
      xi = x.to_i
      yi = y.to_i
      if xi.in?(0...Termbox.width) && yi.in?(0...Termbox.height)
        Termbox.change(xi, yi, fg, bg)
      end
    end

    def append_echo(engine, x : Decimal, y : Decimal, fg : Color, bg : Color, quote : Quote)
      fg, bg = to_tb_color(fg), to_tb_color(bg)
      xi = x.to_i
      yi = y.to_i
      if xi.in?(0...Termbox.width) && yi.in?(0...Termbox.height)
        Termbox.print(xi, yi, fg, bg, quote.string[...Termbox.width - xi])
      end
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
