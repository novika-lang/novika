require "sdl"
require "sdl/ttf"
require "../src/novika"

SDL.init(SDL::Init::VIDEO)
SDL::TTF.init

at_exit { SDL.quit }
at_exit { SDL::TTF.quit }

WINDOW   = SDL::Window.new("SDL tutorial", 1280, 720)
RENDERER = SDL::Renderer.new(WINDOW, SDL::Renderer::Flags::ACCELERATED | SDL::Renderer::Flags::PRESENTVSYNC)

FONT         = SDL::TTF::Font.new(File.join(__DIR__, "ttf", "OpenSans-VariableFont_wdth,wght.ttf"), 12)
CONSOLE_FONT = SDL::TTF::Font.new(File.join(__DIR__, "ttf", "SpaceMono-Regular.ttf"), 10)

SPACE = CONSOLE_FONT.render_blended(" ", SDL::Color[0, 0, 0], ascii: true)

# A naive representation of a console color, enough to emulate
# Novika's requirements.
record ConsColor, r : Int32, g : Int32, b : Int32 do
  include Novika::Form

  Black = ConsColor.new(0, 0, 0)
  White = ConsColor.new(0xff, 0xff, 0xff)

  # Converts to SDL color.
  def to_sdl
    SDL::Color[r, g, b]
  end

  def to_s(io)
    io << "Color(" << r << ", " << g << ", " << b << ")"
  end
end

class IOMod
  include Novika::Package

  def initialize(@player : Player)
    @ichan = Channel(String?).new
  end

  def self.id
    "io overrides"
  end

  def inject(into target)
    target.at("echo", "( F -- ): shows Form in the console.") do |world|
      quote = world.stack.drop.enquote(world)
      @player.println(quote.string)
    end

    target.at("readLine", <<-END
    ( Pf -- Aq true/false ): prompts the user with Prompt form.
     Leaves Answer quote, and an accepted (true) / rejected (false)
     bool. If rejected, Answer quote is empty.
    END
    ) do |world|
      prompt = world.stack.drop.enquote(world)
      @player.println(prompt.string)
      @player.request_user_input(@ichan)
      answer = @ichan.receive
      Novika::Quote.new(answer || "").push(world)
      Novika::Boolean[!answer.nil?].push(world)
    end
  end
end

class ConsMod
  include Novika
  include Package

  private getter! console : ConsoleActivity?

  @timeout = -1
  @keyboard : SDL::Event::Keyboard?

  def initialize(@player : Player)
  end

  def self.id
    "console overrides"
  end

  def inject(into target)
    target.at("console:on", "( -- ): enables Console API, switches to alt. buffer") do
      @console ||= @player.request_console
    end

    target.at("console:off", "( -- ): disables Console API, switches to normal buffer") do
      @console.try &.close
      @console = nil
    end

    target.at("console:256", "( -- ): enables 256 color output") { }
    target.at("console:truecolor", "( -- ): enables truecolor output") { }
    target.at("console:compat", "( -- ): enables compat (normal) color output") { }

    target.at("console:color", "( Rd Gd Bd -- C  ): creates RGB color from decimals") do |world|
      b = world.stack.drop.assert(world, Decimal)
      g = world.stack.drop.assert(world, Decimal)
      r = world.stack.drop.assert(world, Decimal)
      ConsColor.new(r.to_i, g.to_i, b.to_i).push(world)
    end

    target.at("console:setPrimary", "( Fc Bc -- ): clear Fg, Bg colors, default print color") do |world|
      console.bg = world.stack.drop.assert(world, ConsColor)
      console.fg = world.stack.drop.assert(world, ConsColor)
    end

    target.at("console:getPrimary", "( -- Fc Bc ): get primary Fg, Bg colors") do |world|
      console.fg.push(world)
      console.bg.push(world)
    end

    target.at("console:width", "( -- W ): leaves console width (in columns)") do |world|
      Decimal.new(console.cols).push(world)
    end

    target.at("console:height", "( -- W ): leaves console height (in rows)") do |world|
      Decimal.new(console.rows).push(world)
    end

    target.at("console:setTimeout", "( Tms -- ): set input timeout (in ms)") do |world|
      @timeout = world.stack.drop.assert(world, Decimal).to_i
    end

    target.at("console:getTimeout", "( Tms -- ): get input timeout (in ms)") do |world|
      Decimal.new(@timeout).push(world)
    end

    target.at("console:peek", "( -- ): consumes input during timeout") do |world|
      case @timeout
      when .zero?
        @keyboard = console.request_keyboard?
      when .negative?
        # Negative timeout: wait for input for as long as needed.
        chan = Channel(SDL::Event::Keyboard).new
        console.request_keyboard(chan)
        @keyboard = chan.receive
      end
    end

    target.at("console:hadKeyPressed", "( -- Sb ): leaves whether there was a key press event") do |world|
      Boolean[!!@keyboard].push(world)
    end

    target.at("console:getKeyPressed", "( -- Kq ): leaves recent key pressed. Dies if none.") do |world|
      world.die("use hadKeyPressed") unless keyboard = @keyboard

      repr =
        case keyboard.mod
        when .ctrl?
          case keyboard.sym
          when .backquote?    then "CTRL_TILDE"
          when .key_2?        then "CTRL_2"
          when .a?            then "CTRL_A"
          when .b?            then "CTRL_B"
          when .c?            then "CTRL_C"
          when .d?            then "CTRL_D"
          when .e?            then "CTRL_E"
          when .f?            then "CTRL_F"
          when .g?            then "CTRL_G"
          when .h?            then "BACKSPACE"
          when .i?            then "TAB"
          when .j?            then "CTRL_J"
          when .k?            then "CTRL_K"
          when .l?            then "CTRL_L"
          when .m?            then "ENTER"
          when .n?            then "CTRL_N"
          when .o?            then "CTRL_O"
          when .p?            then "CTRL_P"
          when .q?            then "CTRL_Q"
          when .r?            then "CTRL_R"
          when .s?            then "CTRL_S"
          when .t?            then "CTRL_T"
          when .u?            then "CTRL_U"
          when .v?            then "CTRL_V"
          when .w?            then "CTRL_W"
          when .x?            then "CTRL_X"
          when .y?            then "CTRL_Y"
          when .z?            then "CTRL_Z"
          when .leftbracket?  then "CTRL_3"
          when .key_3?        then "ctrl_3"
          when .key_4?        then "BACKSLASH"
          when .backslash?    then "CTRL_BACKSLASH"
          when .key_5?        then "CTRL_RSQ_BRACKET"
          when .rightbracket? then "CTRL_RSQ_BRACKET"
          when .key_6?        then "CTRL_6"
          when .key_7?        then "CTRL_UNDERSCORE"
          when .slash?        then "CTRL_UNDERSCORE"
          when .underscore?   then "CTRL_UNDERSCORE"
          when .key_8?        then "BACKSPACE"
          end
        when .shift?
          if keyboard.sym.tab?
            "BACK_TAB"
          else
            # Todo: bad, needs some work, possibly enumeration
            # by hand.
            keyboard.sym.to_s
          end
        else
          case keyboard.sym
          when .backspace? then "BACKSPACE"
          when .tab?       then "TAB"
          when .return?    then "ENTER"
          when .escape?    then "CTRL_3"
          when .space?     then "SPACE"
          when .f1?        then "F1"
          when .f2?        then "F2"
          when .f3?        then "F3"
          when .f4?        then "F4"
          when .f5?        then "F5"
          when .f6?        then "F6"
          when .f7?        then "F7"
          when .f8?        then "F8"
          when .f9?        then "F9"
          when .f10?       then "F10"
          when .f11?       then "F11"
          when .f12?       then "F12"
          when .insert?    then "INSERT"
          when .delete?    then "DELETE"
          when .home?      then "HOME"
          when .end?       then "END"
          when .pageup?    then "PGUP"
          when .pagedown?  then "PGDN"
          when .up?        then "ARROW_UP"
          when .down?      then "ARROW_DOWN"
          when .left?      then "ARROW_LEFT"
          when .right?     then "ARROW_RIGHT"
          else
            # Todo: bad, needs some work, possibly enumeration
            # by hand.
            keyboard.sym.to_s.downcase
          end
        end

      # TODO:
      #   MOUSE_LEFT       = (0xffff - 23)
      #   MOUSE_RIGHT      = (0xffff - 24)
      #   MOUSE_MIDDLE     = (0xffff - 25)
      #   MOUSE_RELEASE    = (0xffff - 26)
      #   MOUSE_WHEEL_UP   = (0xffff - 27)
      #   MOUSE_WHEEL_DOWN = (0xffff - 28)

      Quote.new(repr || "").push(world)
    end

    target.at("console:isKeyChar", "( Kq -- Sb ): leaves whether Key quote is a single-character key") do |world|
      Boolean[world.stack.drop.assert(world, Quote).string.size == 1].push(world)
    end

    target.at("console:print", "( Q X Y -- ): prints Quote with primary colors") do |world|
      y = world.stack.drop.assert(world, Decimal)
      x = world.stack.drop.assert(world, Decimal)
      q = world.stack.drop.assert(world, Quote)
      console.print(x.to_i, y.to_i, q.string)
    end

    target.at("console:present", "( -- ): syncs internal buffer and console") do |world|
      console.present
    end

    target.at("console:clear", "( -- ): clears console with primary colors") do |world|
      console.clear
    end
  end
end

class Player
  def initialize(@global : Novika::Block, @activity : FileActivity, @path : String)
    @world = Novika::Engine.new
    @toplevel = Novika::Block.new(@global)
    IOMod.new(self).inject(@toplevel)
    ConsMod.new(self).inject(@toplevel)
  end

  delegate :print, :println, :request_user_input, :request_console, to: @activity

  def play
    spawn do
      begin
        Novika.run(@world, @toplevel, Path[@path])
        @global.import!(from: @toplevel)
      rescue e : Novika::EngineFailure
        e.report(STDOUT)
      end
    end
  end
end

class InputMgr
  def initialize(@activity : FileActivity, @index : Int32, @prompt : String, @answer : Channel(String?))
    @ans = ""
  end

  def accept
    @answer.send(@ans)
  end

  def reject
    @answer.send(nil)
  end

  def add(char)
    @ans += char
    @activity.print(@index, @prompt + @ans)
  end
end

# Abstract superclass of all activities.
abstract class Activity
  # Returns children of this activity.
  getter children : Array(Activity)? { [] of Activity }

  # Returns global X coordinate.
  abstract def x
  # Sets global X coordinate.
  abstract def x=(x : Int32)

  # Returns global Y coordinate.
  abstract def y
  # Sets global X coordinate.
  abstract def y=(y : Int32)

  # Returns width.
  abstract def w
  # Returns height.
  abstract def h

  # Presents this activity using *renderer*.
  abstract def present(renderer)

  # Returns whether contains *px*, *py*.
  def inc?(px, py)
    x <= px <= x + w && y <= py <= y + h
  end

  # Moves this activity and all its children to *px*, *py*
  # global coordinates.
  def to(px, py)
    dx, self.x = px - x, px
    dy, self.y = py - y, py
    children.each do |child|
      child.to(child.x + dx, child.y + dy)
    end
  end

  # Returns whether this activity wants to handle event at
  # the given *px*, *py* coordinate.
  def wants_at?(px, py)
    children.any? &.wants_at?(px, py) || inc?(px, py)
  end

  # Applies *name* method with coords.
  private macro distrib(name, rest = [] of Nil)
    children.reverse_each do |child|
      if child.wants_at?(px, py)
        child.{{name}}(x, y, {{*rest}})
        return true
      end
    end
  end

  # Handles motion event at *px*, *y* coordinates.
  def motion(px, py)
    distrib(motion)
  end

  # Handles mouse button pressed at *px*, *py* coordinates.
  def press(px, py)
    distrib(press)
  end

  # Handles mouse button released at *px*, *py* coordinates.
  def release(px, py)
    distrib(release)
  end

  # Handles keyboard events.
  def keyboard(px, py, event)
    distrib(keyboard, [event])
  end

  # Handles *string* input via keyboard.
  def input(px, py, string)
    distrib(input, [string])
  end
end

# Adds support of dragging and dropping to an activity.
module Draggable
  @delta : {Int32, Int32}?

  def wants_at?(px, py)
    super || !!@delta
  end

  def press(px, py)
    return if super
    @delta = {px - x, py - y}
  end

  # Disables dragging mode.
  def release(px, py)
    @delta = nil
    super
  end

  def motion(px, py)
    if delta = @delta
      to(px - delta[0], py - delta[1])
    else
      super
    end
  end
end

# Button to play a file activity.
class PlayButton < Activity
  HOVER = SDL::Color[0xce, 0xce, 0xce]

  getter w : Int32, h : Int32
  property x : Int32, y : Int32

  @label : SDL::Surface
  @hover = false

  def initialize(@activity : FileActivity, @x, @y)
    @label = FONT.render_blended("Play", FileActivity::FG)
    @w = @label.width + 6
    @h = @label.height + 4
  end

  def wants_at?(px, py)
    @hover = inc?(px, py)
  end

  def release(px, py)
    return if super
    @activity.play
  end

  def present(renderer)
    if @hover
      renderer.draw_color = HOVER
      renderer.fill_rect(x, y, w, h)
    end
    renderer.copy(@label, dstrect: SDL::Rect[x + 3, y + 2, @label.width, @label.height])
  end
end

abstract struct ConsCmd
end

struct CmdPrint < ConsCmd
  def initialize(@x : Int32, @y : Int32, @string : String)
  end

  def execute(console)
    console.buffer[@y].map_with_index! do |cell, index|
      next cell if index < @x
      break cell if index >= @x + @string.size
      cell.copy_with(fg: console.fg, bg: console.bg, char: @string[index - @x])
    end
  end
end

class ConsoleActivity < Activity
  include Draggable

  property x = 0
  property y = 0

  getter w : Int32
  getter h : Int32

  # Foreground color. Changing alone affects only consequent
  # prints/clears.
  property fg = ConsColor::White

  # Background color. Changing alone affects only consequent
  # prints/clears.
  property bg = ConsColor::Black

  # Holds the console buffer: consists of row arrays and cells
  # in those row arrays.
  getter buffer : Array(Array(Cell)) do
    Array(Array(Cell)).new(rows) do |row|
      Array(Cell).new(cols) do |col|
        # Fill with whitespace cells.
        Cell.new(row, col, ' ', fg, bg)
      end
    end
  end

  # Command stack. Commands are executed from left to right
  # upon `present`.
  @commands = [] of ConsCmd

  record Cell, row : Int32, col : Int32, char : Char, fg : ConsColor, bg : ConsColor do
    def present(renderer, ox, oy)
      x = ox + col * SPACE.width
      y = oy + row * SPACE.height

      unless char.whitespace?
        # Draw the cell contents (quickly):
        chartext = CONSOLE_FONT.render_blended(char.to_s, fg.to_sdl, bg.to_sdl)
      end

      # Draw outer cell:
      renderer.draw_color = bg.to_sdl
      renderer.fill_rect(x, y, SPACE.width, SPACE.height)

      return unless chartext

      renderer.copy(chartext, dstrect: SDL::Rect[x, y, chartext.width, chartext.height])
    end
  end

  def initialize(@activities : Array(Activity))
    @w = SPACE.width * cols
    @h = SPACE.height * rows
  end

  # Returns the amount of columns.
  def cols
    80
  end

  # Returns the amount of rows.
  def rows
    24
  end

  # Closes this console activity.
  def close
    @activities.delete(self)
  end

  @keychan : Channel(SDL::Event::Keyboard)?
  @last_key : SDL::Event::Keyboard?

  def request_keyboard(@keychan)
  end

  def request_keyboard?
    @last_key
  end

  def keyboard(x, y, event)
    return if super

    if event.pressed?
      @keychan.try &.send(event)
      @last_key = event
      @keychan = nil
    end
  end

  # Clears the contents of this console with `fg`, `bg` colors.
  def clear
    @buffer = nil
    @commands.clear
  end

  # Prints *string* starting at column *x*, row *y*.
  def print(x, y, string)
    @commands << CmdPrint.new(x, y, string)
  end

  # Sync model with view.
  def present
    @commands.each &.execute(self)
    @commands.clear
  end

  def present(renderer)
    buffer.each &.each &.present(renderer, x, y)
  end
end

class FileActivity < Activity
  include Draggable

  BG  = SDL::Color[0xee, 0xee, 0xee]
  FG  = SDL::Color[0x33, 0x33, 0x33]
  BOR = SDL::Color[0xce, 0xce, 0xce]

  getter w : Int32, h : Int32
  property x : Int32, y : Int32

  @label : SDL::Surface
  @strings = [] of {String, SDL::Surface}
  @inpchan : InputMgr?

  getter! button, player

  def initialize(@activities : Array(Activity), global : Novika::Block, @x : Int32, @y : Int32, filename : String)
    @label = FONT.render_blended(filename, FG)
    @w = @label.width + 50
    @h = @label.height + 20
    @player = Player.new(global, self, filename)
    @button = PlayButton.new(self, @x + @label.width + 10 + 5, @y + @h // 4)
    children << button
  end

  delegate :play, to: player

  def input(x, y, string)
    return if super
    @inpchan.try &.add(string)
  end

  def keyboard(x, y, event)
    return if super
    return unless chan = @inpchan

    case event.sym
    when .return?
      chan.accept
      @inpchan = nil
    when .escape?
      chan.reject
      @inpchan = nil
    end
  end

  def request_console
    ConsoleActivity.new(@activities).tap { |it| @activities << it }
  end

  def request_user_input(channel : Channel(String?))
    if ifwd = @inpchan
      ifwd.accept
    else
      @inpchan = InputMgr.new(self, @strings.size - 1, @strings.last[0], channel)
    end
  end

  # Prints *string* below file name in the file activity.
  def println(string)
    print(@strings.size, string)
  end

  # Prints *string* below file name in the file activity without
  # making  a new line.
  def print(string)
    if @strings.empty?
      prev = ""
    else
      prev = @strings.pop[0]
    end
    println(prev + string)
  end

  def print(index, string)
    surf = FONT.render_blended(string, FG)

    if @strings.empty?
      @h += 10
    end
    if index < @strings.size
      @strings.delete_at(index)
    elsif index == @strings.size
      @h += surf.height
    end

    @w = Math.max(surf.width + 20, @w)
    @strings.insert(index, {string, surf})
  end

  def present(renderer)
    renderer.draw_color = BOR
    renderer.fill_rect(@x - 1, @y - 1, @w + 2, @h + 2)
    renderer.draw_color = BG
    renderer.fill_rect(@x, @y, @w, @h)
    renderer.copy(@label, dstrect: SDL::Rect[x = @x + 10, y = @y + 10, @label.width, @label.height])
    y += @label.height
    unless @strings.empty?
      y += 10
    end
    button.present(renderer)
    @strings.each do |(_, surf)|
      renderer.copy(surf, dstrect: SDL::Rect[x, y, surf.width, surf.height])
      y += surf.height
    end
  end
end

activities = [] of Activity

global = Novika::Block.new
kernel = Novika::Packages::Kernel.new
math = Novika::Packages::Math.new
kernel.inject(global)
math.inject(global)

closed = false
prev_drop_coords = nil
clock = Time.utc

until closed
  current = Time.utc
  delta = current - clock
  clock = current

  while event = SDL::Event.poll
    LibSDL.get_mouse_state(out mouse_x, out mouse_y)

    activity = nil
    activities.reverse_each do |it|
      if it.wants_at?(mouse_x, mouse_y)
        break activity = it
      end
    end

    case event
    when SDL::Event::Quit then closed = true
    when SDL::Event::MouseMotion
      activity.try &.motion(mouse_x, mouse_y)
    when SDL::Event::MouseButton
      case event
      when .pressed?  then activity.try &.press(mouse_x, mouse_y)
      when .released? then activity.try &.release(mouse_x, mouse_y)
      end
    when SDL::Event::Keyboard
      activity.try &.keyboard(mouse_x, mouse_y, event)
    when SDL::Event::Drop
      filename = Path[event.filename]
      if File.directory?(filename)
        filenames = Dir.glob("#{filename}/**/*.nk")
      else
        filenames = [filename.to_s]
      end
      filenames.each_with_index do |name, index|
        if activity || index > 0
          mouse_x += 20
          mouse_y += 20
        end
        activities << FileActivity.new(activities, global, mouse_x, mouse_y, name)
      end
    when SDL::Event::TextInput
      activity.try &.input(mouse_x, mouse_y, event.text[0].chr.to_s)
    end
  end

  RENDERER.draw_color = SDL::Color[255, 255, 255]
  RENDERER.clear
  activities.each &.present(RENDERER)
  RENDERER.present

  # Either give time to other fibers, or sleep a lot (the less
  # the more time it is required to render a frame).
  sleep Math.max(1.millisecond, 60.milliseconds - delta)
end
