require "big"
require "./tape"
require "colorize"
require "./primitives"

NKRX = /
    (?<num>         \d+) (?:\s+|$)
  | (?<bb>           \[) (?:\s+|$)
  | (?<be>           \]) (?:\s+|$)
  | (?<word>   [^"'\s]+)
  |'(?<quote>     [^']*)'
  |"(?<comment>   [^"]*)"
  |\s+
/x

class FormDied < Exception
end

module Form
  def die(details)
    raise FormDied.new(details)
  end

  def sel(a, b)
    a
  end

  def opened(world)
    open(world)
  end

  def open(world)
    push(world)
  end

  def push(world)
    world.stack.add(self)
  end

  def prevable?
    false
  end

  def assert(type : T.class) forall T
    is_a?(T) ? self : die("bad type: #{self.class}, expected: #{type}")
  end

  def echo(io)
    io.puts(self)
  end
end

module Tabular
  abstract def at?(name : String)
  abstract def die(details)

  def at(name : String)
    at?(name) || die("undefined table property: #{name}")
  end
end

struct BigDecimal
  include Form
end

class String
  include Form

  def open(world)
    return lchop.push(world) if starts_with?('#')

    if entry = world.cont.at?(self)
      entry.open(world)
    else
      # Run the lookup fallback block, '/default'.
      world.stack.add(self)
      world.cont.at("/default").open(world)
    end
  end
end

abstract struct Entry
  protected getter form : Form

  def initialize(@form)
  end

  delegate :push, :prevable?, to: form

  def open(world)
    push(world)
  end
end

struct PushEntry < Entry
end

struct OpenEntry < Entry
  def open(world)
    form.open(world)
  end
end

struct Builtin
  include Form

  protected getter code : World ->

  def initialize(@code)
  end

  def prevable?
    true
  end

  def open(world)
    code.call(world)
  end

  def to_s(io)
    io << "[native code]"
  end
end

struct Quote
  include Form

  protected getter string : String

  def initialize(@string, unesc = false)
    if unesc
      @string = string
        .gsub("\\n", '\n')
        .gsub("\\t", '\t')
        .gsub("\\r", '\r')
        .gsub("\\v", '\v')
    end
  end

  def +(other)
    Quote.new(string + other.string)
  end

  def echo(io)
    io.puts(string)
  end

  def to_s(io)
    io << "'"; string.dump_unquoted(io); io << "'"
  end
end

abstract struct Boolean
  include Form

  def self.[](bool)
    bool ? True.new : False.new
  end

  def self.same?(a : Reference, b : Reference)
    Boolean[a.same?(b)]
  end

  def self.same?(a, b)
    Boolean[a == b]
  end
end

struct True < Boolean
  def to_s(io)
    io << "true"
  end
end

struct False < Boolean
  def sel(a, b)
    b
  end

  def to_s(io)
    io << "false"
  end
end

class Block
  include Form
  include Tabular

  protected getter tape : Tape(Form) { Tape(Form).new }
  protected getter table : Hash(String, Entry) { {} of String => Entry }

  getter! parent : Block?
  getter prototype : Block

  def initialize(@parent = nil, @prototype = self)
  end

  protected def tape(default = nil)
    @tape ? yield tape : default
  end

  protected def table(default = nil)
    @table ? yield table : default
  end

  def empty?
    tape(true, &.empty?)
  end

  def flat?
    table(true, &.empty?)
  end

  def add(form)
    tap { tape.add(form) }
  end

  def to(index)
    to?(index) || die("cursor out of bounds: #{index}")
  end

  def top
    tape &.top? || die("no top for block")
  end

  def drop
    tape &.drop? || die("cannot drop at start")
  end

  def count
    tape(0, &.count)
  end

  def cursor
    tape(0, &.cursor)
  end

  def each
    tape &.each { |item| yield item }
  end

  def to?(index)
    self if tape index.zero? ? true : false, &.to?(index)
  end

  def at(index : Int32)
    tape &.at?(index) || die("index out of bounds")
  end

  def at(name : String, entry : Entry)
    table[name] = entry
  end

  def at(name : String, form : Form)
    table[name] = PushEntry.new(form)
  end

  def at(name : String, &code : World ->)
    table[name] = OpenEntry.new Builtin.new(code)
  end

  def has?(name : String)
    table &.has_key?(name)
  end

  def at?(name : String)
    table &.[name]? || parent?.try &.at?(name)
  end

  def attach(other : Block)
    tape.replace(other.tape)
  end

  def detach
    Block.new(parent?).tap do |copy|
      tape.each do |form|
        copy.add(form)
      end
    end
  end

  def prevable?
    true
  end

  def opened(world)
    push(world)
  end

  def open(world)
    world.conts.add instance.to(0)
  end

  def instance(parent = self)
    inst = Block.new(parent, prototype)
    tape.each do |form|
      inst.add(form.is_a?(Block) ? form.instance(inst) : form)
    end
    inst
  end

  def slurp(source)
    start, block = 0, self

    while NKRX.match(source, pos: start)
      if match = $~["num"]?
        block.add(match.to_big_d)
      elsif match = $~["word"]?
        block.add(match)
      elsif match = $~["quote"]?
        block.add Quote.new(match, unesc: true)
      elsif match = $~["comment"]?
        # block.describe(match) if block.empty?
      elsif $~["bb"]?
        block = Block.new(block)
      elsif $~["be"]?
        block = block.parent.tap &.add(block)
      end

      start += $0.size
    end

    self
  end

  def to_s(io)
    io << "[ "
    io << tape << " " unless empty?
    io << ". " << table.keys.join(' ') << " " unless flat?
    io << "]"
  end
end

class World
  include Form
  include Tabular

  getter conts : Block
  getter stacks : Block

  def initialize
    @conts = Block.new
    @stacks = Block.new
    stacks.add(Block.new)
  end

  def cont
    conts.top.assert(Block)
  end

  def stack
    stacks.top.assert(Block)
  end

  def at?(name : String)
    case name
    when "conts"  then conts
    when "stacks" then stacks
    end
  end

  def open(start : Block)
    conts.add start.to(0)

    until conts.empty?
      while cont.to?(cont.cursor + 1)
        form = cont.top
        begin
          form.opened(self)
        rescue e : FormDied
          handler = cont.at("/died")
          stack.add Quote.new(e.message.not_nil!)
          handler.open(self)
        end
      end

      conts.drop
    end
  end

  def to_s(io)
    io << "[world object]"
  end
end

source = File.read("basis.nk")

world = World.new
require "benchmark"

block = Block.new(primitives)
block.slurp(source)

begin
  world.open(block)
rescue e : Exception
  e.inspect_with_backtrace(STDOUT) unless e.is_a?(FormDied)

  puts e.message.colorize.red.bold

  count = world.conts.count
  (0...count).each do |index|
    cont = world.conts.at(index).as(Block)
    output = "  IN #{cont.top.colorize.bold}"
    output = output.ljust(32)
    excerpt = ("… #{cont.same?(block) ? "toplevel" : cont}"[0, 64] + " …").colorize.dark_gray
    print output, excerpt
    puts
  end
end
