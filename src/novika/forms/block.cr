module Novika
  # The regex that splits Novika source code into morphemes.
  MORPHEMES = /
      (?<num> [-+]?\d(?:[\d_]*\d)?(?:\.\d(?:[\d_]*\d)?)?) (?=\.|\s+|$)
    | (?<bb> \[)
    | (?<be> \])
    | (?<qword> \#[^"'\s\[\]]+)
    | (?<word> [^"'\s\.\[\]]+|\.)
    |'(?<quote> (?:[^'\\]|\\[ntrv'])*)'
    |"(?<comment> (?:[^"\\]|\\.)*)"
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
  class Block
    include Form
    extend HasDesc

    # Maximum amount of forms to display in block string representation.
    MAX_COUNT_TO_S = 128

    # Maximum amount of forms to display in string representation
    # of *nested* blocks.
    MAX_NESTED_COUNT_TO_S = 12

    # Block to word hook name.
    AS_WORD = Word.new("*asWord")

    # Block to quote hook name.
    AS_QUOTE = Word.new("*asQuote")

    # Block to decimal hook name.
    AS_DECIMAL = Word.new("*asDecimal")

    # Block to boolean hook name.
    AS_BOOLEAN = Word.new("*asBoolean")

    # Block to quoted word hook name.
    AS_QUOTED_WORD = Word.new("*asQuotedWord")

    # Whether this block is a leaf. A block is a leaf when
    # it has no blocks in its tape.
    protected property? leaf = true

    # Returns the tape of this block.
    protected property tape = Tape(Form).new

    # Returns the table of this block.
    protected property table : ITable = Table.new

    # Holds a reference to the parent block (them all in a
    # linked list of ancestors).
    property! parent : Block?

    # Returns the prototype of this block. Block instances return
    # their prototype (AST) blocks, AST blocks return themselves.
    getter! prototype : Block

    # String comment of this block. It normally describes what
    # this block does.
    @comment : String?

    def initialize(@parent : Block? = nil, @prototype = self, @table = Table.new)
    end

    protected def initialize(*,
                             @parent : Block?,
                             @tape : Tape(Form),
                             @table = Table.new,
                             @prototype = self,
                             @leaf = true)
    end

    def desc(io : IO)
      io << (prototype.comment? || "a block")
    end

    def self.desc(io)
      io << "a block"
    end

    # Returns this block's comment, or nil if the comment was
    # not defined or is empty.
    protected def comment? : String?
      @comment unless @comment.try &.empty?
    end

    # Sets the block comment of this block to *comment*
    # in case it doesn't have a comment already.
    def describe_with?(comment comment_ : String) : String?
      @comment = comment_ unless @comment
    end

    # See the same method in `Tape`.
    delegate :cursor, :each, :count, :at?, to: tape

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
          match = match
            .gsub("\\'", '\'')
            .gsub("\\n", '\n')
            .gsub("\\t", '\t')
            .gsub("\\r", '\r')
            .gsub("\\v", '\v')

          block.add Quote.new(match)
        elsif match = $~["comment"]?
          if block.count.zero?
            match = match.gsub("\\\"", '"')
            block.describe_with?(dedent match)
          end
        elsif $~["bb"]?
          block = self.class.new(block)
        elsif $~["be"]?
          block = block.parent.tap &.add(block)
        end

        start += $0.size
      end

      die("missing closing bracket") unless same?(block)

      self
    end

    # Lists all name forms in this block's table.
    def ls : Array(Form)
      table.names
    end

    # Imports entries from *donor* to this block's table by
    # mutating this block's table.
    def import!(from donor : Block) : self
      tap { table.import!(donor.table) }
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

    # Adds *form* after the cursor.
    def inject(form : Form)
      self.tape = tape.inject(form)
    end

    # Drops and returns the element after the cursor. Dies if
    # cursor is at the end.
    def eject : Form
      self.tape, _ = tape.eject? || die("eject out of bounds")
    end

    # Returns form after cursor, and moves cursor past it.
    #
    # Similar to `eject`, but doesn't modify the block.
    def thru
      self.tape, _ = tape.thru? || die("thru out of bounds")
    end

    # Returns the table entry corresponding to *name*, or dies.
    def at(name : Form) : Entry
      at?(name) || die("undefined table property: #{name}")
    end

    # Returns the table entry corresponding to *name*.
    def at?(name : Form) : Entry?
      table.get(name) { parent?.try &.at?(name) }
    end

    # Returns whether this table has an entry corresponding
    # to *name*.
    def has?(name : Form)
      !!at?(name)
    end

    # Returns the form at *index* in the tape. Dies if *index*
    # is out of bounds. See `Tape#at?`.
    def at(index : Int32) : Form
      tape.at?(index) || die("index out of bounds")
    end

    # Binds *name* to *entry* in this block's table.
    def at(name : Form, entry : Entry) : self
      tap { table.set(name, entry) }
    end

    # Dies: mutable keys disallowed.
    def at(name : Block, entry) : self
      die("mutable keys are disallowed, and block is mutable")
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

    # Slices this block at cursor. This results in two halves,
    # which are consequently returned.
    def slice : {Block, Block}
      lhs, rhs = tape.slice

      {Block.new(parent: self, tape: lhs),
       Block.new(parent: self, tape: rhs)}
    end

    # Removes and returns the top form. Dies if none.
    def drop : Form
      top.tap { self.tape = tape.drop? || raise "unreachable" }
    end

    # Adds a continuation for an instance of this block to
    # *engine*. *stack* may be provided to be the stack the
    # instance will operate on.
    def open(engine : Engine, over stack : Block = engine.stack) : self
      tap { engine.schedule(self, stack) }
    end

    # Returns a shallow copy of this block.
    def shallow : Block
      self.class.new(parent: parent?, tape: tape.copy, table: table, prototype: prototype)
    end

    # Replaces this block's tape with *other*'s.
    def attach(other : Block) : self
      self.tape = tape.replace(other.tape)
      self
    end

    # Loose equality: for two blocks to be loosely equal, their
    # tapes and their tables must be loosely equal.
    #
    # Supports recursive (reflection) equality, e.g.:
    #
    # ```novika
    # [ ] $: a
    # a a shove
    # a 0 fromLeft a = "=> true"
    # ```
    def ==(other)
      return false unless other.is_a?(self)
      return true if same?(other)
      return false unless count == other.count
      result = false
      executed = exec_recursive(:==) do
        result = tape == other.tape && table == other.table
      end
      executed && result
    end

    # Creates and returns an instance of this block, under the
    # given *parent*.)
    def instance(parent reparent : Block = self, __tr = nil) : Block
      if leaf?
        return self.class.new(parent: reparent, tape: tape.copy, prototype: prototype)
      end

      # If this block isn't a leaf, we need to copy its sub-blocks
      # as well. Note that `map!` allows to skip quickly (i.e., is
      # actual noop) when the block returns nil.
      #
      # We need to create a translation map which will replace
      # any reflections of this block with *copy*. E.g.,
      #
      #   >>> [ ] $: a
      #   >>> a a <<
      #   === [ [a reflection] ]
      #   >>> new
      #
      # ... should create a *copy* of `a`, then go thru its
      # child blocks depth first (`__tr` boards `instance`
      # to do that) and replace all reflections with the copy.
      #
      # Therefore, the fact that they are reflections of the
      # parent is maintained.
      __tr ||= {} of Block => Block
      __tr[self] = copy = self.class.new(parent: reparent, tape: tape.copy, prototype: prototype)
      copy.tape = copy.tape.map! do |form|
        next unless form.is_a?(Block)
        __tr[form]? || form.instance(copy, __tr: __tr)
      end
      copy.leaf = false
      copy
    end

    # Assert through the result of running *name*'s value in
    # this block's table.
    private def assert?(engine : Engine, name : Form, type : T.class) : T? forall T
      form = table.get(name) { return }
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
      when Decimal.class    then assert?(engine, AS_DECIMAL, type)
      when Quote.class      then assert?(engine, AS_QUOTE, type)
      when Word.class       then assert?(engine, AS_WORD, type)
      when Boolean.class    then assert?(engine, AS_BOOLEAN, type)
      when QuotedWord.class then assert?(engine, AS_QUOTED_WORD, type)
      end || afail(T)
    end

    def to_quote(engine : Engine) : Quote
      assert?(engine, AS_QUOTE, Quote) || super
    end

    # Appends a string representation of this block to *io* in
    # which only forms in the negative and positive *vicinity*
    # of this block's cursor are present, and the word before
    # the cursor is emphasized.
    #
    # Does not respect `MAX_COUNT_TO_S`. Does not display quotes.
    # Does not display nested blocks.
    def spot(io, vicinity = 10)
      io << "["

      b = (cursor - vicinity).clamp(0..count - 1)
      e = (cursor + vicinity).clamp(0..count - 1)

      (b..e).each do |index|
        form = at(index)
        focus = index == cursor - 1

        Colorize.with.bold.toggle(focus).surround(io) do
          case form
          when Block then io << " […]"
          when Quote then io << " '…'"
          else
            io << " " << form
          end
        end

        io << " |".colorize.red if focus
      end

      io << " ]"
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

      unless table.empty?
        io << " . "; ls.join(io, ' ')
      end

      io << " ]"
      io << "+" unless same?(prototype)
    end
  end
end
