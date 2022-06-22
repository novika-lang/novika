require "big"
require "colorize"
require "file_utils"

require "./tape"
require "./primitives"

module Novika
  # The regex that splits Novika source code into morphemes.
  MORPHEMES = /
      (?<num>          \d+) (?:\s+|$)
    | (?<bb>            \[) (?:\s+|$)
    | (?<be>            \]) (?:\s+|$)
    | (?<qword> \#[^"'\s]+)
    | (?<word>    [^"'\s]+)
    |'(?<quote>      [^']*)'
    |"(?<comment>    [^"]*)"
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

    # Rects to this form being opened in *world*.
    def open(world)
      opened(world)
    end

    # Reacts to this form's enclosing block being opened in *world*.
    def opened(world)
      push(world)
    end

    # Adds this form to *block*.
    def push(block : Block)
      block.add(self)
    end

    # Pushes this form onto *world*'s active stack.
    def push(world : World)
      push(world.stack)
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

  # Supports the word `at`.
  module ReadableTable
    protected abstract def die(details)

    # Returns the table entry for *name*, or nil.
    def at?(name : Form)
    end

    # Returns the table entry for *name*, or dies.
    def at(name : Form)
      at?(name) || die("undefined table property: #{name}")
    end

    # Returns whether this table has *name* table entry.
    def has?(name)
      !!at?(name)
    end
  end

  # Words open entries they're assigned to in the table
  # of their enclosing block.
  struct Word
    include Form

    DIED     = Word.new("*died")
    FALLBACK = Word.new("*fallback")

    protected getter id : String

    def initialize(@id)
    end

    delegate :starts_with?, to: id

    # Converts this word into a `QuotedWord`.
    def quote
      QuotedWord.new(id)
    end

    def opened(world)
      if entry = world.block.at?(self)
        entry.open(world)
      elsif fallback = world.block.at?(FALLBACK)
        world.stack.add(quote)
        fallback.open(world)
      else
        die("definition for #{self} not found in the enclosing block(s)")
      end
    end

    def to_s(io)
      io << id
    end

    def_equals_and_hash id
  end

  # Quoted words are words prefixed by '#': e.g., `#foo`. It lets
  # you keep automatic word opening one manual `open` away.
  struct QuotedWord
    include Form

    protected getter id : String

    # Quotes the given *id*.
    def initialize(@id)
    end

    # Converts this quoted word into a `Word`.
    def unquote
      Word.new(id)
    end

    def opened(world)
      unquote.push(world)
    end

    def to_s(io)
      io << '#' << id
    end

    def_equals_and_hash id
  end

  # A representation for decimal numbers inside Novika.
  struct Decimal
    include Form

    protected getter val : BigDecimal

    def initialize(@val : BigDecimal)
    end

    def initialize(object)
      initialize(object.to_big_d)
    end

    def to_i
      val.to_i
    end

    # Returns the sum of this and *other* decimal numbers.
    def +(other)
      Decimal.new(val + other.val)
    end

    # Returns the difference between this and *other* decimal numbers.
    def -(other)
      Decimal.new(val - other.val)
    end

    # Returns the product of this and *other* decimal numbers.
    def *(other)
      Decimal.new(val * other.val)
    end

    # Returns the quotient of this and *other* decimal numbers.
    def /(other)
      Decimal.new(val / other.val)
    end

    # Returns the remainder of this and *other* decimal numbers.
    def %(other)
      Decimal.new(val.to_big_i % other.val.to_big_i)
    end

    # Returns whether this decimal is smaller than *other*.
    def <(other)
      val < other.val
    end

    def to_s(io)
      io << val
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

  # A kind of entry that, when opened, in turn opens its
  # value form.
  class OpenEntry < Entry
    # Opens this entry's value form in *world*.
    def open(world)
      form.open(world)
    end
  end

  class Block
    include Form
    include ReadableTable

    protected getter tape = Tape(Form).new
    protected getter table = {} of Form => Entry
    protected getter audience : Array(self ->) { [] of self -> }

    # Returns and allows to set whether this block is a leaf.
    # A block is a leaf when it has no blocks in its tape.
    protected property? leaf = true

    # Holds a reference to the parent block (them all in a
    # linked list of ancestors).
    property! parent : Block?

    # Returns the prototype of this block. Block instances return
    # their prototype (AST) blocks, AST blocks return themselves.
    getter! prototype : Block

    def initialize(@parent : Block? = nil, @prototype = self)
    end

    protected def initialize(
      @parent : Block?,
      @tape : Tape(Form),
      @table = {} of Form => Entry,
      @prototype = self,
      @leaf = true
    )
    end

    # Notifies the audience, if any. Returns self.
    protected def notify
      tap { audience.each &.call(self) if @audience }
    end

    # Notifies the audience (if any) after the block
    protected def notify
      yield self

      notify
    end

    # Updates the tape and notifies the audience.
    protected def tape=(@tape)
      notify
    end

    # Subscribe to changes in this block.
    def track(listener : self ->)
      audience << listener
    end

    # :ditto:
    def track(&listener : self ->)
      track(listener)
    end

    # See the same method in `Tape`.
    delegate :cursor, :each, :count, to: tape

    # Parses all forms from string *source*, and adds them to
    # this block. Returns self.
    def slurp(source)
      start, block = 0, self

      while MORPHEMES.match(source, pos: start)
        if match = $~["num"]?
          block.add Decimal.new(match)
        elsif match = $~["word"]?
          block.add Word.new(match)
        elsif match = $~["qword"]?
          block.add QuotedWord.new(match.lchop)
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

    # Returns whether the tape is empty.
    def empty?
      count.zero?
    end

    # Returns whether the table is empty.
    def list?
      table.empty?
    end

    # See `Tape#next?`.
    def next?
      self.tape, _ = tape.next? || return
    end

    # Moves tape cursor to *index* and returns self, or dies if
    # *index* is out of bounds. See `Tape#to?`.
    def to(index)
      tap &.tape = tape.to?(index) || die("cursor index out of bounds")
    end

    # Returns the table entry for *name*.
    def at?(name : Form)
      table.fetch(name) { parent?.try &.at?(name) }
    end

    # Returns the form at *index* in the tape. Dies if *index*
    # is out of bounds. See `Tape#at?`.
    def at(index : Int32)
      tape.at?(index) || die("index out of bounds")
    end

    # Binds *name* to *entry* in this block's table.
    def at(name : Form, entry : Entry)
      notify { table[name] = entry }
    end

    # Tracks *name* for rehashing, binds *name* to *entry*.
    def at(name : Block, entry)
      name.track { table.rehash }

      notify { table[name] = entry }
    end

    # Binds *name* to *form* in this block's table.
    def at(name : Form, form : Form)
      at name, Entry.new(form)
    end

    # Makes an `OpenEntry` called *name* for *code* wrapped
    # in `Builtin`.
    def at(name : Word, &code : World ->)
      at name, OpenEntry.new Builtin.new(code)
    end

    # :ditto:
    def at(name : String, &code : World ->)
      at Word.new(name), OpenEntry.new Builtin.new(code)
    end

    # Returns whether this block's table has an entry called *name*.
    def has?(name)
      table.has_key?(name)
    end

    # Adds *form* to the tape. See `Tape#add`.
    def add(form)
      self.leaf = false if form.is_a?(Block)

      tap &.tape = tape.add(form)
    end

    # Returns the top form, dies if none. See `Tape#top?`.
    def top
      tape.top? || die("no top for block")
    end

    # Duplicates form before the cursor, dies if none.
    def dupl
      add(top)
    end

    # Swaps two forms before the cursor, dies if they are
    # not found.
    def swap
      a = drop
      b = drop
      add(a)
      add(b)
    end

    # Removes and returns the top form. Dies if none.  See `Tape#drop?`.
    def drop
      top.tap { self.tape = tape.drop? || raise "unreachable" }
    end

    # Returns an array of words defined by this block.
    def ls
      table.keys
    end

    # Adds a continuation for an instance of this block to
    # *world*. *stack* may be provided for the stack this
    # block will operate on.
    def open(world, over stack = world.stack)
      world.continue with: self, over: stack
    end

    # Returns a new block with a shallow copy of this block's
    # *tape* set as its tape.
    def detach
      Block.new(parent?, tape.copy, table, prototype)
    end

    # Replaces this block's tape with *other*'s.
    def attach(other)
      self.tape = tape.replace(other.tape)
    end

    # Creates and returns an instance of this block, under
    # the given *reparent*.
    def instance(reparent = self)
      if leaf?
        # Leaf, just copy the tape. Leaf? is true by default,
        # no need to pass that down.
        Block.new(reparent, tape.copy, prototype: prototype)
      else
        # Has sub-blocks, must instantiate them as well.
        Block.new(reparent, prototype).tap do |copy|
          tape.each do |form|
            form = form.instance(copy) if form.is_a?(Block)
            form.push(copy)
          end
        end
      end
    end

    def spotlight(io)
      # junk todo
      io << "[ ".colorize.dark_gray.bold

      fmt = tape.each
        .map_with_index do |form, index|
          form = form.is_a?(Block) ? "[…]" : form.to_s
          form = form.colorize
          delta = cursor - index
          form.bold.toggle(delta == 1) if (cursor - index).abs.in?(0..10)
        end
        .insert(0, "…".colorize.dark_gray)
        .insert(cursor, "|".colorize.red.bold)
        .<<("…".colorize.dark_gray)
        .compact
        .join(io, ' ')

      io << " ]".colorize.dark_gray.bold
    end

    def to_s(io)
      # junk todo

      io << "[ "

      tape.each
        .map { |form| form.is_a?(Block) ? "[…]" : form.to_s }.to_a
        .insert(cursor, "|")
        .join(io, ' ')

      unless list?
        io << " . "; ls.join(io, ' ')
      end

      io << " ]"
    end
  end

  # A block (instance) with a stack block. Novika interpreter's
  # main goal is to exhaust continuations.
  record Continuation, block : Block, stack : Block do
    include Form
    include ReadableTable

    def at?(name : Word)
      case name.id
      when "block" then block
      when "stack" then stack
      end
    end

    def to_s(io)
      io << "｢ B:#{block.object_id} S:#{stack.object_id} ｣"
    end
  end

  # Novika interpreter and context.
  class World
    include Form

    # Returns the continuations block.
    getter conts = Block.new

    # Returns the active continuation.
    getter cont : Continuation { conts.top.assert(Continuation) }

    # Returns the active continuation's block.
    getter block : Block { cont.block }

    # Returns the active continuation's stack.
    getter stack : Block { cont.stack }

    def initialize
      # Subscribe and invalidate cache on change:
      conts.track do
        @cont = nil
        @block = nil
        @stack = nil
      end
    end

    # Adds an instance of *form* block to the continuations.
    def continue(with form : Block, over stack)
      conts.add Continuation.new(form.instance.to(0), stack)
    end

    # Adds an empty continuation with *stack*, and opens *form*.
    def continue(with form, over stack)
      conts.add Continuation.new(block, stack)
      form.open(self)
    end

    # Exhausts the continuations.
    def exhaust
      # junk todo

      until conts.empty?
        while form = block.next?
          begin
            form.opened(self)
          rescue e : FormDied
            if handler = block.at?(Word::DIED)
              stack.add Quote.new(e.message.not_nil!)
              handler.open(self)
              next
            end

            print "Sorry: ".colorize.red.bold, e.message.not_nil!, "."
            puts
            puts

            ind = "  "
            conts.each.with_index do |cc, index|
              cc = cc.assert(Continuation)
              bar1 = index == conts.count - 1 ? "→" : "|"
              bar2 = index == conts.count - 1 ? " " : "|"

              print ind, bar1, " IN ".colorize.bold
              cc.block.spotlight(STDOUT)
              puts

              print ind, bar2, " OVER ".colorize.bold, cc.stack
              puts
            end

            puts
            abort "Sorry! Exiting because of this error."
          end
        end

        conts.drop
      end
    end
  end
end

CDIR  = "directory".colorize.blue
CFILE = "file".colorize.green

def help : NoReturn
  abort <<-END
  Welcome to Novika, and thanks for trying it out!
  
  One or more arguments must be provided for Novika to properly pick
  up what you're trying to run. For instance:

    $ novika     core             example.nk
                 ----             ----------
                 a #{CDIR}        a #{CFILE}

  (1) When you provide a #{CDIR}, Novika will run all *.nk files in
      that directory. First, *.nk files in the directory itself are run,
      and then that process is repeated in the sub-directories. For any
      given directory, the main file in that directory is dirname.nk. it
      is always run first.

  (2) In other words, a #{CDIR} provided in arguments has higher priority
      than a #{CFILE}. But then, files in those directories have higher priority
      than sub-directories.

  You can try running the following command:

    $ novika core hello.nk
  
  END
end

record Mod, entry : Path? = nil, files = [] of Path do
  def add(file)
    files << file
  end
end

# Collects files and directories as stated in `help`, starting
# at *root*, and saves them in *mods*.
def collect(mods, root : Path)
  if File.file?(entry = root / "#{root.stem}.nk")
    mods[root] = mod = Mod.new(entry)
  else
    mods[root] = mod = Mod.new
  end

  Dir.glob(root / "*.nk") do |path|
    path = Path[path]
    mod.add(path) unless path == entry
  end

  Dir.glob(root / "/*/") do |path|
    collect(mods, Path[path])
  end
end

def import(recpt : Novika::Block, donor : Novika::Block)
  donor.ls.each do |name|
    unless name.is_a?(Novika::Word) && name.starts_with?('_')
      recpt.at name, donor.at(name)
    end
  end
end

def run(world, toplevel, path : Path)
  {% unless flag?(:release) %}
    puts path.colorize.dark_gray
  {% end %}
  source = File.read(path)
  stack = Novika::Block.new
  block = Novika::Block.new(toplevel).slurp(source)
  world.conts.add Novika::Continuation.new(block.to(0), stack)
  world.exhaust
  import(toplevel, block)
end

help if ARGV.empty?

cwd = Path[FileUtils.pwd]

dirs = [] of Path
files = [] of Path

ARGV.each do |arg|
  case File
  when .directory?(arg) then dirs << Path[arg]
  when .file?(arg)      then files << Path[arg]
  else
    abort "#{arg.colorize.bold} is neither a file nor a directory avaliable in #{cwd.to_s}"
  end
end

mods = {} of Path => Mod

dirs.each do |path|
  collect(mods, Path[path])
end

world = Novika::World.new
prims = Novika::Block.new
Novika::Primitives.inject(into: prims)
toplevel = Novika::Block.new(prims)

# Evaluate module entries fisrt, if any.
mods.each_value.select(&.entry).each do |mod|
  run(world, toplevel, mod.entry.not_nil!)
end

# Then evaluate all other files.
mods.each_value do |mod|
  mod.files.each do |file|
    run(world, toplevel, file)
  end
end

# Then evalute user's files.
files.each do |file|
  run(world, toplevel, file)
end
