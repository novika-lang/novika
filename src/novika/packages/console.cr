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

      # target.at("console:open", "( FDq -- ): enables Console API for fd") do
      # TODO
      # end

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

      target.at("console:color", "( Rd Gd Bd -- ): creates RGB color from decimals") do |world|
        b = world.stack.drop.assert(world, Decimal)
        g = world.stack.drop.assert(world, Decimal)
        r = world.stack.drop.assert(world, Decimal)
        Termbox::Color[r.to_i, g.to_i, b.to_i].push(world)
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:setPrimary", "( Fc Bc -- ): clear Fg, Bg colors, default print color") do |world|
        self.pbg = world.stack.drop.assert(world, Termbox::Color)
        self.pfg = world.stack.drop.assert(world, Termbox::Color)
        Termbox.clear(pfg, pbg)
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:getPrimary", "( -- Fc Bc ): get primary Fg, Bg colors") do |world|
        pfg.push(world)
        pbg.push(world)
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:width", "( -- W ): leaves console width (in columns)") do |world|
        Decimal.new(Termbox.width).push(world)
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:height", "( -- W ): leaves console height (in rows)") do |world|
        Decimal.new(Termbox.height).push(world)
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:setTimeout", "( Tms -- ): set input timeout (in ms)") do |world|
        self.timeout = world.stack.drop.assert(world, Decimal).to_i
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:getTimeout", "( Tms -- ): set input timeout (in ms)") do |world|
        Decimal.new(timeout).push(world)
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:peek", "( -- ): consumes input during timeout") do |world|
        self.event = Termbox.peek?(timeout)
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:hadKeyPressed", "( -- Sb ): leaves whether there was a key press event") do |world|
        Boolean[!!event.try &.is_a?(Termbox::Event::KeyEvent)].push(world)
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:getKeyPressed", "( -- Kq ): leaves recent key pressed. Dies if none.") do |world|
        ok = false
        (event.try &.as?(Termbox::Event::KeyEvent)).try do |it|
          Quote.new((it.key || it.char || break).to_s).push(world)
          ok = true
        end
        world.die("use hadKeyPressed") unless ok
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:isKeyChar", "( Kq -- Sb ): leaves whether Key quote is a single-character key") do |world|
        Boolean[!Termbox::Key.parse?(world.stack.drop.assert(world, Quote).string)].push(world)
      end

      target.at("console:print", "( Q X Y -- ): prints Quote with primary colors") do |world|
        y = world.stack.drop.assert(world, Decimal)
        x = world.stack.drop.assert(world, Decimal)
        q = world.stack.drop.assert(world, Quote)
        Termbox.print(x.to_i, y.to_i, pfg, pbg, q.string)
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:present", "( -- ): syncs internal buffer and console") do |world|
        Termbox.present
      rescue e
        Termbox.disable
        raise e
      end

      target.at("console:clear", "( -- ): clears console with primary colors") do |world|
        Termbox.clear
      rescue e
        Termbox.disable
        raise e
      end
    end
  end
end
