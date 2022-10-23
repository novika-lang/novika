require "colorize"

module Novika::Features::Impl
  class Ink < IInk
    COMPAT = {
      Color.rgb(0x00, 0x00, 0x00) => :black,
      Color.rgb(0x80, 0x00, 0x00) => :red,
      Color.rgb(0x00, 0x80, 0x00) => :green,
      Color.rgb(0x80, 0x80, 0x00) => :yellow,
      Color.rgb(0x00, 0x00, 0x80) => :blue,
      Color.rgb(0x80, 0x00, 0x80) => :magenta,
      Color.rgb(0x00, 0x80, 0x80) => :cyan,
      Color.rgb(0xc0, 0xc0, 0xc0) => :light_gray,
      Color.rgb(0x80, 0x80, 0x80) => :dark_gray,
      Color.rgb(0xff, 0x00, 0x00) => :light_red,
      Color.rgb(0x00, 0xff, 0x00) => :light_green,
      Color.rgb(0xff, 0xff, 0x00) => :light_yellow,
      Color.rgb(0x00, 0x00, 0xff) => :light_blue,
      Color.rgb(0xff, 0x00, 0xff) => :light_magenta,
      Color.rgb(0x00, 0xff, 0xff) => :light_cyan,
      Color.rgb(0xff, 0xff, 0xff) => :white,
    }

    private def append_echo(engine, object)
      engine.die(NO_SYSTEM_ECHO_ERROR) unless system = bundle[ISystem]?

      system.append_echo(engine, Quote.new(object.to_s))
    end

    def with_emphasis_append_echo(engine, form : Form)
      append_echo(engine, form.to_quote.string.colorize.bold)
    end

    def with_reverse_append_echo(engine, form : Form)
      append_echo(engine, form.to_quote.string.colorize.reverse)
    end

    def with_color_append_echo(engine, fg : Color?, bg : Color?, form : Form)
      string = form.to_quote.string

      colorful = string.colorize
      colorful = colorful.fore(COMPAT[fg.closest(COMPAT.keys)]) if fg
      colorful = colorful.back(COMPAT[bg.closest(COMPAT.keys)]) if bg

      append_echo(engine, colorful)
    end
  end
end
