module Novika
  # The regex that splits Novika source code into morphemes.
  MORPHEMES = /
    (?<num>       \-?\d+) (?:\s+|$)
  | (?<bb>            \[) (?:\s+|$)
  | (?<be>            \]) (?:\s+|$)
  | (?<qword> \#[^"'\s]+)
  | (?<word>    [^"'\s]+)
  |'(?<quote>      [^']*)'
  |"(?<comment>    [^"]*)"
  |\s+
  /x

  # Blocks are very fundamental to Novika.
  #
  # They are a kind of AST node, they hold continuations and
  # are continuations, they are arrays, stacks, and hash tables,
  # all at the same time.
  #
  # In this sense, blocks have *roles*. But any block can be
  # any role, and change its role as often and whenever it
  # wants or needs to.
  #
  # Blocks can be subscribed to for tracking changes at runtime,
  # or diffed and/or patched analytically, etc.
  class Block
    include Form
    extend HasDesc

    include ReadableTable

    # Maximum amount of forms to display in block string representation.
    MAX_COUNT_TO_S = 128

    # Maximum amount of forms to display in string representation
    # of *nested* blocks.
    MAX_NESTED_COUNT_TO_S = 12

    # Block to boolean hook name.
    AS_BOOL = Word.new("*asBool")

    # Block to word hook name.
    AS_WORD = Word.new("*asWord")

    # Block to quote hook name.
    AS_QUOTE = Word.new("*asQuote")

    # Block to decimal hook name.
    AS_DECIMAL = Word.new("*asDecimal")

    # Returns and allows to set whether this block is a leaf.
    # A block is a leaf when it has no blocks in its tape.
    private property? leaf = true

    # Returns the string comment of this block. It normally
    # describes what this block does.
    private property comment : String?

    # Returns the tape of this block.
    getter tape = Tape(Form).new

    # Returns the table of this block.
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
      @table = Table.new,
      @prototype = self,
      @leaf = true
    )
    end

    def desc(io : IO)
      io << (comment? || "a block")
    end

    def self.desc(io)
      io << "a block"
    end

    # Notifies the audience, if any.
    private def notify : self
      tap { audience.each &.call(self) if @audience }
    end

    # Notifies the audience (if any) after the block.
    private def notify : self
      yield self

      notify
    end

    # Updates the tape and notifies the audience.
    #
    # Note: Tape object itself is immutable. When this block
    # changes, it replaces its tape with a new one. This is
    # why this method works as it should.
    protected def tape=(@tape)
      notify
    end

    # Returns this block's comment, or nil if the comment was
    # not defined or is empty.
    protected def comment? : String?
      comment unless comment.try &.empty?
    end

    # Subscribes to changes in this block.
    def track(listener : self ->) : self
      tap { audience << listener }
    end

    # :ditto:
    def track(&listener : self ->) : self
      track(listener)
    end

    # Sets the block comment of this block to *comment*
    # in case it doesn't have a comment already.
    def describe_with?(comment comment_ : String) : String?
      self.comment = comment_ unless comment?
    end

    # See the same method in `Tape`.
    delegate :cursor, :each, :count, :at?, to: tape

    # Loose equality: for two blocks to be loosely equal, their
    # tapes and their tables must be loosely equal.
    def_equals tape, table

    # Removes common indentation from this string. Lines that
    # consist entirely of white space are replaced with a
    # single newline character.
    private def dedent(string) : String
      return string if string.empty?

      first = true
      lines_ = string.lines(chomp: false)
      indent = nil

      lines_.each do |line|
        # Skip blank lines.
        next if line.blank?

        # Get the indentation of the line.
        level = line.each_char.take_while(&.whitespace?).size
        if level.zero? && first
          # Skip the line if it's first, and its indentation
          # is zero.
          next first = false
        end

        indent = level if indent.nil? || level < indent
      end

      String.build do |io|
        lines_.each do |line|
          if line.blank?
            io << '\n'
          elsif !first # a zero-indent line was skipped
            io << line
            first = true
          else
            io << line[indent..]
          end
        end
      end
    end

    # Parses all forms in string *source*, and adds them to
    # this block.
    def slurp(source : String) : self
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
          block.describe_with?(dedent match) if block.empty?
        elsif $~["bb"]?
          block = self.class.new(block)
        elsif $~["be"]?
          block = block.parent.tap &.add(block)
        end

        start += $0.size
      end

      self
    end

    # Returns whether the *tape* is empty.
    def empty? : Bool
      count.zero?
    end

    # Returns whether the *table* is empty.
    def list? : Bool
      table.empty?
    end

    # Returns whether this block's table has an entry whose
    # name is *name*.
    def has?(name : Form) : Bool
      table.has_key?(name)
    end

    # Imports entries from *donor* to this block's table by
    # mutating this block's table.
    def import!(from donor : Block) : self
      notify { table.merge!(donor.table) }
    end

    # See `Tape#next?`.
    def next? : Form?
      self.tape, _ = tape.next? || return
    end

    # Moves tape cursor to *index*. Dies if *index* is out
    # of bounds. See `Tape#to?`.
    def to(index : Int32) : self
      self.tape = tape.to?(index) || die("cursor index out of bounds")
      self
    end

    # Returns the table entry corresponding to *name*.
    def at?(name : Form) : Entry?
      table.fetch(name) { parent?.try &.at?(name) }
    end

    # Returns the form at *index* in the tape. Dies if *index*
    # is out of bounds. See `Tape#at?`.
    def at(index : Int32) : Form
      tape.at?(index) || die("index out of bounds")
    end

    # Binds *name* to *entry* in this block's table.
    def at(name : Form, entry : Entry) : self
      notify { table[name] = entry }
    end

    # Tracks *name* for rehashing, binds *name* to *entry*.
    def at(name : Block, entry) : self
      name.track { table.rehash }

      notify { table[name] = entry }
    end

    # Binds *name* to *form* in this block's table.
    def at(name : Form, form : Form) : self
      at name, Entry.new(form)
    end

    # Makes an `OpenEntry` called *name* for *code* wrapped
    # in `Builtin`.
    def at(name : Word, desc = "a builtin", &code : Engine ->) : self
      at name, OpenEntry.new Builtin.new(desc, code)
    end

    # :ditto:
    def at(name : String, desc = "a builtin", &code : Engine ->) : self
      at Word.new(name), OpenEntry.new Builtin.new(desc, code)
    end

    # Adds *form* to the tape.
    def add(form : Form) : self
      self.leaf = false if form.is_a?(Block)
      self.tape = tape.add(form)
      self
    end

    # Returns the top form, dies if none.
    def top : Form
      tape.top? || die("no top for block")
    end

    # Duplicates the form before the cursor, dies if none.
    def dupe : self
      add(top)
    end

    # Swaps two forms before the cursor, dies if none.
    def swap : self
      a = drop
      b = drop
      add(a)
      add(b)
    end

    # Removes and returns the top form. Dies if none.
    def drop : Form
      top.tap { self.tape = tape.drop? || raise "unreachable" }
    end

    # Returns an array of names found in this block's table.
    def ls : Array(Form)
      table.keys
    end

    # Adds a continuation for an instance of this block to
    # *engine*. *stack* may be provided to be the stack the
    # instance will operate on.
    def open(engine : Engine, over stack : Block = engine.stack) : self
      tap { engine.schedule(self, stack) }
    end

    # Returns a shallow copy of this block.
    def shallow : Block
      self.class.new(parent?, tape.copy, table, prototype)
    end

    # Replaces this block's tape with *other*'s.
    def attach(other : Block) : self
      self.tape = tape.replace(other.tape)
      self
    end

    # Creates and returns an instance of this block, under the
    # given *parent*.)
    def instance(parent reparent : Block = self) : Block
      if leaf?
        # Leaf, just copy the tape. Leaf? is true by default,
        # no need to pass that down.
        self.class.new(reparent, tape.copy, prototype: prototype)
      else
        # Has sub-blocks, must instantiate them as well.
        self.class.new(reparent, prototype).tap do |copy|
          tape.each do |form|
            form = form.instance(copy) if form.is_a?(Block)
            copy.add(form)
          end
        end
      end
    end

    # Assert through the result of running *name*'s value in
    # this block's table.
    private def assert?(engine : Engine, name : Form, type : T.class) : T? forall T
      return unless form = at?(name)
      result = engine[form, push(self.class.new)].drop
      unless result.is_a?(Block) && same?(result)
        result.assert(engine, T)
      end
    end

    # Converts this block into the given *type*. Code execution
    # may be required, hence the need for *engine*. If failed,
    # same as `Form#assert`.
    def assert(engine : Engine, type : T.class) : T forall T
      return self if is_a?(T)

      case T
      when Decimal.class then assert?(engine, AS_DECIMAL, type)
      when Quote.class   then assert?(engine, AS_QUOTE, type)
      when Word.class    then assert?(engine, AS_WORD, type)
      when Boolean.class then assert?(engine, AS_BOOL, type)
      end || afail(T)
    end

    def enquote(engine : Engine) : Quote
      assert?(engine, AS_QUOTE, Quote) || super
    end

    def spotlight(io)
      # junk todo
      io << "[ ".colorize.dark_gray.bold

      fmt = tape.each.map_with_index do |form, index|
        form = form.is_a?(Block) ? "[…]" : form.to_s
        form = form.colorize
        delta = cursor - index
        if (cursor - index).abs.in?(0..10)
          form.bold.toggle(delta == 1)
        end
      end

      fmt
        .insert(0, "…".colorize.dark_gray)
        .insert(cursor, "|".colorize.red.bold)
        .push("…".colorize.dark_gray)
        .compact
        .join(io, ' ')

      io << " ]".colorize.dark_gray.bold
    end

    def to_s(io, nested = false)
      # junk todo
      executed = true

      contents = String.build do |conio|
        executed = exec_recursive(:to_s) do
          if count > (nested ? MAX_NESTED_COUNT_TO_S : MAX_COUNT_TO_S)
            conio << "… " << count << " forms here …"
          else
            tape.each
              .map { |form| form.is_a?(Block) ? String.build { |str| form.to_s(str, nested: true) } : form.to_s }.to_a
              .insert(cursor, "|")
              .join(conio, ' ')
          end
        end
      end

      if executed
        io << "[ " << contents
      else
        io << "[a reflection]"
        return
      end

      unless list?
        io << " . "; ls.join(io, ' ')
      end

      io << " ]"
    end
  end
end
