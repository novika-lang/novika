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

struct QuotedWord
  include Form

  protected getter word : String

  def initialize(@word)
  end

  def open(world)
    word.push(world)
  end

  def to_s(io)
    io << '#' << word
  end
end

class String
  include Form

  def open(world)
    if entry = world.cont.at?(self)
      entry.open(world)
    else
      # Run the lookup fallback block, '/default'.
      world.stack.add(self)
      world.cont.at("/default").open(world)
    end
  end
end

abstract class Entry
  protected getter form : Form

  def initialize(@form)
  end

  delegate :push, :prevable?, to: form

  def submit(@form)
    self
  end

  def open(world)
    push(world)
  end
end

class PushEntry < Entry
end

class OpenEntry < Entry
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

  alias Table = Hash(String, Entry)

  protected getter tape : Tape(Form) { Tape(Form).new }
  protected getter table : Table { Table.new }

  protected getter reach : Table { Table.new }
  protected property? leaf = true

  getter! parent : Block?
  getter prototype : Block

  def initialize(
    @parent = nil,
    @prototype = self,
    @reach = nil
  )
  end

  protected def initialize(
    @parent : Block?,
    @tape : Tape(Form),
    @reach : Table,
    @prototype = self,
    @leaf = true
  )
  end

  protected def tape(default = nil)
    @tape ? yield tape : default
  end

  protected def table(default = nil)
    @table ? yield table : default
  end

  def next?
    tape &.next?
  end

  def empty?
    tape(true, &.empty?)
  end

  def flat?
    table(true, &.empty?)
  end

  def add(form)
    tap &.tape.add(form)
  end

  def add(form : Block)
    self.leaf = false

    tap &.tape.add(form)
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

  def to?(index)
    self if tape index.zero? ? true : false, &.to?(index)
  end

  def at(index : Int32)
    tape &.at?(index) || die("index out of bounds")
  end

  def at?(name : String)
    reach[name] ||= table &.[name]? || parent?.try &.at?(name) || return
  end

  def at(name : String, entry : Entry)
    table[name] = reach[name] = entry
  end

  def at(name : String, form : Form)
    at(name, PushEntry.new(form))
  end

  def at(name : String, &code : World ->)
    at(name, OpenEntry.new Builtin.new(code))
  end

  def has?(name : String)
    table &.has_key?(name)
  end

  def attach(other : Block)
    tape.replace(other.tape)
  end

  def detach
    Block.new(parent?, Tape.borrow(tape), reach, leaf: leaf?)
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
    if leaf?
      Block.new(parent, Tape.borrow(tape), reach.dup, prototype, leaf?)
    else
      inst = Block.new(parent, prototype, reach.dup)
      tape.each do |form|
        inst.add(form.is_a?(Block) ? form.instance(inst) : form)
      end
      inst
    end
  end

  def slurp(source)
    start, block = 0, self

    while NKRX.match(source, pos: start)
      if match = $~["num"]?
        block.add(match.to_big_d)
      elsif match = $~["word"]?
        block.add(match.starts_with?('#') ? QuotedWord.new(match.lchop) : match)
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

  @[AlwaysInline]
  def cont
    conts.top.assert(Block)
  end

  @[AlwaysInline]
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
      while form = cont.next?
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
