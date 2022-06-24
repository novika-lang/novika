require "big"
require "colorize"
require "file_utils"

require "./tape"
require "./primitives"

class String
  # Returns whether this string starts with *prefix* but also
  # has other characters after it.
  def prefixed_by?(prefix : String)
    starts_with?(prefix) && size > prefix.size
  end

  # :ditto:
  def prefixed_by?(prefix : Char)
    starts_with?(prefix) && size > 1
  end
end

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

  # Raised when a form dies.
  class FormDied < Exception
    # Returns a string describing the reasons of this death.
    getter details : String

    def initialize(@details)
    end
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

    # Returns a string description of this form.
    def desc
      "a form"
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

    # Returns this form's quote representation. May require
    # Novika code to be run. Hence *world* has to be provided,
    # the name is so strange.
    def enquote(world)
      Quote.new(to_s)
    end
  end

  # Enables support for `entry:fetch`, `entry:exists?`,
  # `entry:isOpenEntry?`, and the derived words.
  module ReadableTable
    abstract def die(details)

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

    # Standard death handler entry name.
    DIED = Word.new("*died")

    # Standard word trap entry name.
    TRAP = Word.new("*trap")

    # Standard to-`Quote` conversion entry name.
    ENQUOTE = Word.new("*enquote")

    # Returns the underlying string id.
    getter id : String

    def initialize(@id)
    end

    def desc
      "a word named #{id}"
    end

    def opened(world)
      if entry = world.block.at?(self)
        entry.open(world)
      elsif trap = world.block.at?(TRAP)
        world.stack.add QuotedWord.new(id)
        trap.open(world)
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

    # Returns the underlying string id.
    getter id : String

    def initialize(@id)
    end

    def desc
      "a quoted word named #{id}"
    end

    # "Peels" off a layer of quoting.
    #
    # ```
    # QuotedWord.new("#foo").unquote   # Word.new("foo")
    # QuotedWord.new("##foo").unquote  # QuotedWord.new("#foo")
    # QuotedWord.new("###foo").unquote # QuotedWord.new("##foo")
    # ```
    def peel
      id.prefixed_by?('#') ? QuotedWord.new(id.lchop) : Word.new(id)
    end

    def opened(world)
      peel.push(world)
    end

    def to_s(io)
      io << '#' << id
    end

    def_equals_and_hash id
  end

  # A representation for decimal numbers inside Novika.
  struct Decimal
    include Form

    # Returns the underlying big decimal value.
    getter val : BigDecimal

    def initialize(@val : BigDecimal)
    end

    def initialize(object)
      initialize(object.to_big_d)
    end

    # Downgrades this decimal into an integer (`Int32`). Dies
    # if this decimal is too large.
    def to_i
      val.to_i
    rescue OverflowError
      die("conversion overflow when downgrading a decimal")
    end

    def desc
      "decimal number #{val}"
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

    getter desc : String

    # :nodoc:
    getter code : World ->

    def initialize(@desc, @code)
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

    # Returns the underlying string.
    getter string : String

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

    def desc
      "quote (aka string in other languages) with value: '#{string.dump_unquoted}'"
    end

    # Concatenates two quotes, and returns the resulting quote.
    def +(other)
      Quote.new(string + other.string)
    end

    def enquote(world)
      self
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
    def desc
      "a boolean representing truth"
    end

    def to_s(io)
      io << "true"
    end

    def_equals_and_hash
  end

  # Represents a falsey `Boolean`. `False` is the only falsey
  # form in Novika.
  struct False < Boolean
    def desc
      "a boolean representing falsehood"
    end

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
    # Returns the form held by this entry.
    getter form : Form

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

    # Maximum amount of forms to display in block's string
    # representation.
    MAX_COUNT_TO_S = 128

    # Maximum amount of forms to display in nested blocks
    # in string representation of this block.
    MAX_NESTED_COUNT_TO_S = 12

    # Returns and allows to set whether this block is a leaf.
    # A block is a leaf when it has no blocks in its tape.
    private property? leaf = true

    # Returns the string comment of this block. It normally
    # describes what this block does.
    private property comment : String?

    # Returns the tape of this block.
    getter tape = Tape(Form).new

    # Retunrs the table of this block.
    getter table = {} of Form => Entry

    # :nodoc:
    #
    # Returns the audience (listeners) for this block.
    getter audience : Array(self ->) { [] of self -> }

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

    # Returns this block's comment, or nil if the comment was
    # not defined or is empty.
    protected def comment?
      comment unless comment.try &.empty?
    end

    def desc
      comment? || "a block"
    end

    # Sets the block comment of this block to *string* in case
    # there is no block comment already. Otherwise, does nothing.
    def describe?(string)
      self.comment = string unless comment?
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
          block.describe?(match.strip) if block.empty?
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

    # Returns whether the table is empty, that is, whether
    # this block is a list block.
    def list?
      table.empty?
    end

    # See `Tape#next?`.
    def next?
      self.tape, _ = tape.next? || return
    end

    # Moves tape cursor to *index* and returns self, or dies
    # if *index* is out of bounds. See `Tape#to?`.
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
    def at(name : Word, desc = "a builtin", &code : World ->)
      at name, OpenEntry.new Builtin.new(desc, code)
    end

    # :ditto:
    def at(name : String, desc = "a builtin", &code : World ->)
      at Word.new(name), OpenEntry.new Builtin.new(desc, code)
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

    # Duplicates the form before the cursor, dies if none.
    def dupl
      add(top)
    end

    # Swaps two forms before the cursor, dies if they're not
    # found. Returns the new top form.
    def swap
      a = drop
      b = drop
      add(a)
      add(b)
    end

    # Removes and returns the top form. Dies if none. See `Tape#drop?`.
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
      world.enable(self, stack)
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

    def enquote(world)
      if enquote = at?(Word::ENQUOTE)
        form = world[enquote, push(Block.new)].drop
        unless form.is_a?(Block) && same?(form)
          return form.enquote(world)
        end
      end

      super
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

    def to_s(io, nested = false)
      # junk todo

      io << "[ "

      if count > (nested ? MAX_NESTED_COUNT_TO_S : MAX_COUNT_TO_S)
        io << "… " << count << " forms here …"
      else
        tape.each
          .map { |form| form.is_a?(Block) ? String.build { |str| form.to_s(str, nested: true) } : form.to_s }.to_a
          .insert(cursor, "|")
          .join(io, ' ')
      end

      unless list?
        io << " . "; ls.join(io, ' ')
      end

      io << " ]"
    end
  end

  # Novika interpreter and context.
  struct World
    include Form

    # Maximum amount of trace entries in error reports. After
    # passing this number, only `MAX_TRACE` *last* entries
    # will be displayed.
    MAX_TRACE = 64

    # Maximum amount of enabled continuations in `conts`. After
    # passing this number, `FormDied` is raised to bring attention
    # to such dangerous depth.
    #
    # NOTE: this number should be forgiving and probably settable
    # from the language.
    MAX_CONTS = 32_000

    # Maximum allowed world nesting. Used, for instance, to
    # prevent very deep recursion in `World::ENQUOTE` et al.
    MAX_WORLD_NESTING = 1000

    # Index of the block in a continuation block.
    C_BLOCK_AT = 0

    # Index of the stack block in a continuation block.
    C_STACK_AT = 1

    # Returns the nesting number. Normally zero, for nested
    # worlds increases with each nest. Allows us to sort of
    # "track" Crystal's call stack and stop nesting when it's
    # becomes dangerously deep.
    private getter nesting : Int32

    # Returns the continuations block (aka continuations stack).
    getter conts = Block.new

    def initialize
      @nesting = 0
    end

    protected def initialize(@nesting)
    end

    # Creates a conventional continuation `Block`.
    #
    # A conventional continuation block consists of two table
    # fields: one for the block, and one for the stack.
    def self.cont(block, stack)
      Block.new
        .add(block)
        .add(stack)
    end

    # Returns the active continuation.
    def cont
      conts.top.assert(Block)
    end

    # Returns the block of the active continuation.
    def block
      cont.at(C_BLOCK_AT).assert(Block)
    end

    # Returns the stack block of the active continuation.
    def stack
      cont.at(C_STACK_AT).assert(Block)
    end

    # Reports about an *error* into *io*.
    def report(e : FormDied, io = STDOUT)
      io << "Sorry: ".colorize.red.bold << e.details << "."
      io.puts
      io.puts

      omitted = Math.max(0, conts.count - MAX_TRACE)
      count = conts.count - omitted

      conts.each.skip(omitted).with_index do |cont_, index|
        cont_ = cont_.assert(Block)
        io << "  " << (index == count - 1 ? '└' : '├') << ' '
        io << "IN".colorize.bold << ' '
        cont_.at(C_BLOCK_AT).assert(Block).spotlight(io)
        io.puts

        io << "  " << (index == count - 1 ? ' ' : '│') << ' '
        io << "OVER".colorize.bold << ' ' << cont_.at(C_STACK_AT).assert(Block)
        io.puts
      end

      io.puts
    end

    # Focal point for adding continuations. Returns self.
    #
    # The place where continuation stack's depth is tracked.
    def enable(other : Block)
      if conts.count > MAX_CONTS
        raise FormDied.new("continuations stack dangerously deep (> #{MAX_CONTS})")
      end

      tap { conts.add(other) }
    end

    # Adds an instance of *form* block to the continuations
    # block, with *stack* set as the continuation stack.
    #
    # Returns self.
    def enable(form : Block, stack)
      enable World.cont(form.instance.to(0), stack)
    end

    # Adds an empty continuation with *stack* as set as the
    # continuation stack, and opens (normally pushes) *form*
    # there immediately.
    #
    # Returns self.
    def enable(form, stack)
      # In case we're running in an empty world, create an
      # empty block for the form.
      enable World.cont(conts.empty? ? Block.new : block, stack)

      tap { form.open(self) }
    end

    # Exhausts all enabled continuations, starting from the
    # topmost (see `Block#top`) continuation in `conts`.
    def exhaust
      until conts.empty?
        while form = block.next?
          begin
            form.opened(self)
          rescue e : FormDied
            if died = block.at?(Word::DIED)
              stack.add(Quote.new(e.details))
              begin
                died.open(self)
                next
              rescue e : FormDied
                puts "DEATH HANDLER DIED".colorize.yellow.bold
              end
            end
            report(e)
            abort("Sorry! Exiting because of this error.")
          end
        end
        conts.drop
      end
    end

    # Enables *form* in this world's offspring, with *stack*
    # set as the stack, and exhausts the offspring. Returns
    # *stack*. Exists to simplify calls to Novika from Crystal.
    # Raises if cannot nest (due to exceeding recursion depth,
    # see `MAX_WORLD_NESTING`).
    def [](form, stack stack_ = stack)
      if nesting > MAX_WORLD_NESTING
        raise FormDied.new(
          "too many worlds (> #{MAX_WORLD_NESTING}) of the same " \
          "origin world:probably deep recursion in a word called " \
          "from native code, such as #{Word::ENQUOTE}")
      end

      world = World.new(nesting + 1)
      world.enable(form, stack_)
      world.exhaust
      stack_
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
    unless name.is_a?(Novika::Word) && name.id.prefixed_by?('_')
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
  world.conts.add Novika::World.cont(block.to(0), stack)
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
