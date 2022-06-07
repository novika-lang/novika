require "big"
require "./tape"
require "colorize"
require "./primitives"

module Novika
  # The regex that splits Novika source code into morphemes.
  MORPHEMES = /
      (?<num>         \d+) (?:\s+|$)
    | (?<bb>           \[) (?:\s+|$)
    | (?<be>           \]) (?:\s+|$)
    | (?<word>   [^"'\s]+)
    |'(?<quote>     [^']*)'
    |"(?<comment>   [^"]*)"
    |\s+
  /x

  # Raised when a form dies. The details of the death are found
  # in the error message.
  class FormDied < Exception
  end

  # Form is an umbrella for words and blocks. Since some words
  # (like numbers, quotes) are just too different from words as
  # we know them, they have their own types directly subordinate
  # to Form.
  module Form
    # Raises `FormDied` providing *details*.
    def die(details)
      raise FormDied.new(details)
    end

    # Selects either *a* or *b*. Novika defines `False` to be the
    # only form selecting *b*. All other forms select *a*.
    def sel(a, b)
      a
    end

    # Reacts to this form's enclosing block being opened in *world*.
    def opened(world)
      open(world)
    end

    # Rects to this form being opened in *world*.
    def open(world)
      push(world)
    end

    # Pushes this form onto *world*'s active stack.
    def push(world)
      world.stack.add(self)
    end

    # Asserts that this form is of the given *type*. Dies if
    # it's not.
    def assert(type : T.class) forall T
      is_a?(T) ? self : die("bad type: #{self.class}, expected: #{type}")
    end

    # Appends this form's `echo` word string representation
    # to *io*.
    def echo(io)
      io.puts(self)
    end
  end

  # Implements table access.
  module ITable
    protected abstract def die(details)

    # Returns the table entry for *name*.
    abstract def at?(name : Form)

    # Returns the table entry for *name*, or dies.
    def at(name : Form)
      at?(name) || die("undefined table property: #{name}")
    end
  end

  struct ::BigDecimal
    include Novika::Form
  end

  # Quoted words are words prefixed by '#': e.g., `#foo`. It lets
  # you keep automatic word opening one manual `open` away.
  struct QuotedWord
    include Form

    protected getter word : String

    # Quotes the given *word*.
    def initialize(@word)
    end

    def open(world)
      word.push(world)
    end

    def to_s(io)
      io << '#' << word
    end

    def_equals_and_hash word
  end

  class ::String
    include Novika::Form

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

  # Represents a table entry. Holds the value form.
  class Entry
    protected getter form : Form

    def initialize(@form)
    end

    # Pushes this entry's value form onto the active stack.
    delegate :push, to: form

    # :ditto:
    def open(world)
      push(world)
    end

    # Makes *form* the value form of this entry.
    def submit(@form)
      self
    end

    def_equals_and_hash form
  end

  # A kind of entry that opens its value form upon retrieval.
  class OpenEntry < Entry
    # Opens this entry's value form in *world*.
    def open(world)
      form.open(world)
    end
  end

  # Wraps a snippet of Crystal (native) code, namely a Crystal
  # `Proc`, for usage in the Novika-world.
  struct Builtin
    include Form

    protected getter code : World ->

    def initialize(@code)
    end

    def open(world)
      code.call(world)
    end

    def to_s(io)
      io << "[native code]"
    end

    def_equals_and_hash code
  end

  # Represents Novika quotes, which are known as strings in most
  # other programming languages.
  struct Quote
    include Form

    protected getter string : String

    # Initializes a quote from the given *string*.
    #
    # If *peel* is set to true, one slash will be removed before
    # every escape sequence in *string*: for example, `\\n` will
    # become `\n`, etc.
    def initialize(@string, peel = false)
      if peel
        @string = string
          .gsub("\\n", '\n')
          .gsub("\\t", '\t')
          .gsub("\\r", '\r')
          .gsub("\\v", '\v')
      end
    end

    # Concatenates two quotes, and returns the resulting quote.
    def +(other)
      Quote.new(string + other.string)
    end

    def echo(io)
      io.puts(string)
    end

    def to_s(io)
      io << "'"; string.dump_unquoted(io); io << "'"
    end

    def_equals_and_hash string
  end

  # Represents a boolean (true/false) value.
  abstract struct Boolean
    include Form

    # Creates a `Boolean` subclass for the given *object*.
    def self.[](object)
      object ? True.new : False.new
    end

    # Returns a `Boolean` for whether two objects, *a* and
    # *b*, are the same.
    def self.same?(a : Reference, b : Reference)
      Boolean[a.same?(b)]
    end

    # :ditto:
    def self.same?(a, b)
      Boolean[a == b]
    end
  end

  # Represents a truthy `Boolean`.
  struct True < Boolean
    def to_s(io)
      io << "true"
    end

    def_equals_and_hash
  end

  # Represents a falsey `Boolean`. `False` is the only falsey
  # form in Novika.
  struct False < Boolean
    def sel(a, b)
      b
    end

    def to_s(io)
      io << "false"
    end

    def_equals_and_hash
  end

  # Blocks are, together with words, the principal forms of Novika,
  # and are at the core of the whole idea.
  #
  # Blocks provide a unified interface to `Tape` and `Table`. On
  # one hand, they are a collection of other forms. On the other,
  # they are objects (through the form to form map called block
  # table, and delegation via `/default`).
  class Block
    include Form
    include ITable

    alias Table = Hash(Form, Entry)

    protected getter tape : Tape(Form) { Tape(Form).new }
    protected getter table : Table { Table.new }

    # Optimization:

    # Returns a table of all retrieved entries.
    protected getter reach : Table { Table.new }

    # Returns and allows to set whether this block is a leaf.
    # A block is a leaf when it has no blocks in the tape.
    #
    # Useful for not copying recursively during instantiation
    # (`instance`). Even though no copies are made, it's still
    # slower than not copying at all.
    protected property? leaf = true

    # Returns the parent of this block. Think of it as the AST
    # parent, observed at parse-time.
    getter! parent : Block?

    # Returns the prototype of this block. Block instances return
    # their prototype (AST) blocks, AST blocks return themselves.
    getter prototype : Block

    def initialize(@parent = nil, @prototype = self)
    end

    protected def initialize(
      @parent : Block?,
      @prototype : Block,
      @reach : Table
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

    # See `Tape#next?`.
    def next?
      tape(&.next?)
    end

    # Returns whether the tape is empty.
    def empty?
      tape(default: true, &.empty?)
    end

    # Returns whether the table is empty.
    def flat?
      table(default: true, &.empty?)
    end

    # Adds *form* to the tape. See `Tape#add`.
    def add(form)
      tap &.tape.add(form)
    end

    # :ditto:
    def add(form : Block)
      self.leaf = false

      tap &.tape.add(form)
    end

    # See `Tape#to?`. Returns self.
    def to?(index)
      self if tape.to?(index)
    end

    # Moves tape cursor to *index* and returns self, or dies if
    # *index* is out of bounds. See `to?`.
    def to(index)
      to?(index) || die("cursor out of bounds: #{index}")
    end

    # Returns the top form (the form before the cursor), dies
    # if none. See `Tape#top?`.
    def top
      tape(&.top?) || die("no top for block")
    end

    # Drops and returns the top form. Dies if none. See `Tape#drop?`.
    def drop
      tape(&.drop?) || die("cannot drop at start")
    end

    # Returns the amount of forms in the tape. Cursor position
    # is ignored.
    def count
      tape(default: 0, &.count)
    end

    # Returns the position of the cursor.
    def cursor
      tape(default: 0, &.cursor)
    end

    # Returns the form at *index* in the tape. Dies if *index*
    # is out of bounds. See `Tape#at?`.
    def at(index : Int32)
      tape &.at?(index) || die("index out of bounds")
    end

    def at?(name : Form)
      reach[name] ||= table(&.[name]?) || parent?.try &.at?(name) || return
    end

    # Binds *name* to *entry* in this block's table.
    def at(name : Form, entry : Entry)
      table[name] = reach[name] = entry
    end

    # Dies, since block names would require some sort of
    # automatic rehashing.
    #
    # TODO: Support this in future revisions by allowing blocks
    # to subscribe to other blocks?
    def at(name : Block, entry)
      die("cannot have blocks as table entry names")
    end

    # Binds *name* to *form* in this block's table.
    def at(name : Form, form : Form)
      at(name, Entry.new(form))
    end

    # Makes an `OpenEntry` called *name* for *code* wrapped
    # in `Builtin`.
    def at(name : Form, &code : World ->)
      at(name, OpenEntry.new Builtin.new(code))
    end

    # Returns whether this block's table has an entry called *name*.
    def has?(name : Form)
      table &.has_key?(name)
    end

    # See `Tape#replace`.
    def attach(other : Block)
      tape.replace(other.tape)
    end

    # Returns a shallow copy of this block.
    def detach
      Block.new(parent?, Tape.borrow(tape), reach, leaf: leaf?)
    end

    def opened(world)
      push(world)
    end

    def open(world)
      world.conts.add instance.to(0)
    end

    # Creates and returns an instance of this block, under the
    # given *parent*.
    def instance(parent = self)
      if leaf?
        Block.new(parent, Tape.borrow(tape), reach.dup, prototype, leaf?)
      else
        Block.new(parent, prototype, reach.dup).tap do |inst|
          tape.each do |form|
            inst.add(form.is_a?(Block) ? form.instance(inst) : form)
          end
        end
      end
    end

    # Parses all forms from string *source*, and adds them to
    # this block. Returns self.
    def slurp(source)
      start, block = 0, self

      while MORPHEMES.match(source, pos: start)
        if match = $~["num"]?
          block.add(match.to_big_d)
        elsif match = $~["word"]?
          block.add(match.starts_with?('#') ? QuotedWord.new(match.lchop) : match)
        elsif match = $~["quote"]?
          block.add Quote.new(match, peel: true)
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
      io << String.build do |buf|
        buf << "[ "
        unless empty?
          executed = exec_recursive(:to_s) { buf << tape << " " }
          break "reflection" unless executed
        end
        buf << ". " << table.keys.join(' ') << " " unless flat?
        buf << "]"
      end
    end

    def_equals_and_hash tape, table
  end

  # Novika interpreter and context, united.
  class World
    include Form
    include ITable

    # Returns the continuations block.
    getter conts : Block

    # Returns the stacks block.
    getter stacks : Block

    def initialize
      @conts = Block.new
      @stacks = Block.new
      stacks.add(Block.new)
    end

    # Returns the active continuation (a `Block`).
    @[AlwaysInline]
    def cont
      conts.top.assert(Block)
    end

    # Returns the active stack (a `Block`).
    @[AlwaysInline]
    def stack
      stacks.top.assert(Block)
    end

    # Provides two fields (hence two possible values for *name*):
    # `#conts` (see `conts`), and `#stacks` (see `stacks`). For
    # any other *name* returns nil.
    def at?(name : Form)
      case name
      when "conts"  then conts
      when "stacks" then stacks
      end
    end

    # Starts the interpreter loop.
    def start
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
end

source = File.read("basis.nk")

world = Novika::World.new
block = Novika::Block.new(Novika.primitives)
block.slurp(source)

begin
  world.conts.add block.to(0)
  world.start
rescue e : Exception
  e.inspect_with_backtrace(STDOUT) unless e.is_a?(Novika::FormDied)

  puts e.message.colorize.red.bold

  count = world.conts.count
  (0...count).each do |index|
    cont = world.conts.at(index).as(Novika::Block)
    output = "  IN #{cont.top.colorize.bold}"
    output = output.ljust(32)
    excerpt = ("… #{cont.same?(block) ? "toplevel" : cont}"[0, 64] + " …").colorize.dark_gray
    print output, excerpt
    puts
  end
end
