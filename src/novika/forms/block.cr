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
    getter table = Table.new

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
end
