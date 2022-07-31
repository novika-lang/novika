{% skip_file unless flag?(:novika_console) %}

require "termbox2"

struct Termbox::Color
  include Novika::Form
end

module Novika::Packages
  class Console
    include Package

    def self.id
      "console"
    end

    property pfg : Termbox::Color = Termbox::Color::White
    property pbg : Termbox::Color = Termbox::Color::Black
    property timeout = -1
    property event : Termbox::BaseEvent?

    def inject(into target)
      target.at("console:on", "( -- ): enables Console API, switches to alt. buffer") do
        Termbox.enable
      end

      target.at("console:off", "( -- ): disables Console API, switches to normal buffer") do
        Termbox.disable
      end

      target.at("console:compat", "( -- ): enables compat (normal) color output") do
        Termbox.set_output_mode(Termbox::OutputMode::Normal)
      end

      target.at("console:256", "( -- ): enables 256 color output") do
        Termbox.set_output_mode(Termbox::OutputMode::M256)
      end

      target.at("console:truecolor", "( -- ): enables truecolor output") do
        Termbox.set_output_mode(Termbox::OutputMode::Truecolor)
      end

      target.at("console:color", "( Rd Gd Bd -- ): creates RGB color from decimals") do |engine|
        b = engine.stack.drop.assert(engine, Decimal)
        g = engine.stack.drop.assert(engine, Decimal)
        r = engine.stack.drop.assert(engine, Decimal)
        Termbox::Color[r.to_i, g.to_i, b.to_i].push(engine)
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:setPrimary", "( Fc Bc -- ): clear Fg, Bg colors, default print color") do |engine|
        self.pbg = engine.stack.drop.assert(engine, Termbox::Color)
        self.pfg = engine.stack.drop.assert(engine, Termbox::Color)
        Termbox.clear(pfg, pbg)
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:getPrimary", "( -- Fc Bc ): get primary Fg, Bg colors") do |engine|
        pfg.push(engine)
        pbg.push(engine)
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:width", "( -- W ): leaves console width (in columns)") do |engine|
        Decimal.new(Termbox.width).push(engine)
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:height", "( -- W ): leaves console height (in rows)") do |engine|
        Decimal.new(Termbox.height).push(engine)
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:setTimeout", "( Tms -- ): set input timeout (in ms)") do |engine|
        self.timeout = engine.stack.drop.assert(engine, Decimal).to_i
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:getTimeout", "( Tms -- ): set input timeout (in ms)") do |engine|
        Decimal.new(timeout).push(engine)
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:peek", "( -- ): consumes input during timeout") do
        self.event = Termbox.peek?(timeout)
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:hadKeyPressed", "( -- Sb ): leaves whether there was a key press event") do |engine|
        Boolean[!!event.try &.is_a?(Termbox::Event::KeyEvent)].push(engine)
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:getKeyPressed", "( -- Kq ): leaves recent key pressed. Dies if none.") do |engine|
        ok = false
        (event.try &.as?(Termbox::Event::KeyEvent)).try do |it|
          Quote.new((it.key || it.char || break).to_s).push(engine)
          ok = true
        end
        engine.die("use hadKeyPressed") unless ok
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:isKeyChar", "( Kq -- Sb ): leaves whether Key quote is a single-character key") do |engine|
        Boolean[!Termbox::Key.parse?(engine.stack.drop.assert(engine, Quote).string)].push(engine)
      end

      target.at("console:print", "( Q X Y -- ): prints Quote with primary colors") do |engine|
        y = engine.stack.drop.assert(engine, Decimal)
        x = engine.stack.drop.assert(engine, Decimal)
        q = engine.stack.drop.assert(engine, Quote)
        Termbox.print(x.to_i, y.to_i, pfg, pbg, q.string)
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:present", "( -- ): syncs internal buffer and console") do
        Termbox.present
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:clear", "( -- ): clears console with primary colors") do
        Termbox.clear
      rescue e
        Termbox.disable
        raise e
      end
    end
  end
end
