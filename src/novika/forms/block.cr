module Novika
  # The regex that splits Novika source code into morphemes.
  MORPHEMES = /
      (?<num> [-+]?\d(?:[\d_]*\d)?(?:\.\d(?:[\d_]*\d)?)?) (?=\.|\s+|\[|\]|$)
    | (?<bb> \[)
    | (?<be> \])
    | (?<qword> \#[^"'\s\[\]]+)
    | (?<word> [^"'\s\.\[\]]+|\.)
    |'(?<quote> (?:[^'\\]|\\[\\ntrv'])*)'
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

    # Maximum amount of forms to display in block string representation.
    MAX_COUNT_TO_S = 128

    # Maximum amount of forms to display in string representation
    # of *nested* blocks.
    MAX_NESTED_COUNT_TO_S = 12

    # Block to word hook name.
    AS_WORD = Word.new("*asWord")

    # Block to color hook name.
    AS_COLOR = Word.new("*asColor")

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

    # Returns the dictionary of this block.
    protected property dict : IDict = Dict.new

    # Holds this block's friends. Friends provide an alternative
    # lookup pathway: when parent hierarchy fails to find an entry
    # matching some name, friends are asked for that entry.
    #
    # Traversal and lookup is performed in reverse insertion
    # order. Therefore, MRO is parent followed by friends from
    # latest friend to oldest friend.
    getter friends : Array(Form) { [] of Form }

    # Holds a reference to the parent block (them all in a
    # linked list of ancestors).
    property! parent : Block?

    # Returns the prototype of this block. Block instances return
    # their prototype (AST) blocks, AST blocks return themselves.
    getter! prototype : Block

    # String comment of this block. It normally describes what
    # this block does.
    @comment : String?

    def initialize(@parent : Block? = nil, @prototype = self, @tape = Tape(Form).new, @dict = Dict.new)
    end

    protected def initialize(*,
                             @parent : Block?,
                             @tape : Tape(Form),
                             @dict = Dict.new,
                             @prototype = self,
                             @leaf = true)
    end

    # Creates an orphan block with *array* being its tape
    # substrate's container. See `Tape.for`.
    def self.for(array : Array(Form))
      Block.new(tape: Tape.for(array))
    end

    def desc(io : IO)
      io << (prototype.comment? || "a block")
    end

    def self.typedesc
      "block"
    end

    # Returns this block's comment, or nil if the comment was
    # not defined or is empty.
    protected def comment? : String?
      @comment unless @comment.try &.empty?
    end

    # Sets the block comment of this block to *comment* in
    # case it doesn't have a comment already.
    #
    # Setting the comment can also be forced by making *force* true.
    def describe_with?(comment : String, force = false) : String?
      @comment = comment if force || !comment?
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
            .gsub(/(?<!\\)\\'/, '\'')
            .gsub(/(?<!\\)\\n/, '\n')
            .gsub(/(?<!\\)\\t/, '\t')
            .gsub(/(?<!\\)\\r/, '\r')
            .gsub(/(?<!\\)\\v/, '\v')
            .gsub(/\\\\/, '\\')
          block.add Quote.new(match)
        elsif match = $~["comment"]?
          if block.count.zero?
            match = match
              .gsub(/(?<!\\)\\"/, '"')
              .gsub(/\\\\/, '\\')
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

    # Yields friends of this block. Asserts each is a block,
    # otherwise, dies (e.g. the user may have mistakenly
    # added some other form).
    def each_friend
      return unless @friends

      friends.reverse_each do |friend|
        unless friend.is_a?(Block)
          die("expected a block, got #{friend.class.typedesc} for a friend")
        end
        yield friend
      end
    end

    # Adds *other* to the friendlist of this block.
    def befriend(other : Block)
      friends << other
    end

    # Removes *other* from the friendlist of this block.
    def unfriend(other : Block)
      return unless @friends

      friends.delete(other)
    end

    # Lists all name forms in this block's dictionary.
    def ls : Array(Form)
      dict.names
    end

    # Imports entries from *donor* to this block's dictionary
    # by mutating this block's dictionary.
    def import!(from donor : Block) : self
      tap { dict.import!(donor.dict) }
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

    # Returns the dictionary entry corresponding to *name*,
    # or dies.
    def at(name : Form) : Entry
      at?(name) || die("undefined dictionary property: #{name}")
    end

    # Returns the dictionary entry corresponding to *name*.
    #
    # Traverses the block hierarchy in the following order:
    #
    # (1) First, this block's dictionary is asked for the entry
    #     corresponding to *name*. If unsuccessful,
    #
    # (2) The parent block's dictionary is asked for the entry
    #     corresponding to *name*. If unsuccessful, the process
    #     is repeated on the parent of parent, etc., until there
    #     is no parent block. If entry is still not found,
    #
    # (3) The delegates of this block are asked for the entry
    #     corresponding to *name*. For each delegate, the
    #     process starting from (1) repeats.
    #
    # (4) If none of this block's delegates have an entry for
    #     *name*, (3) and (4) are repeated on the block's parent.
    #
    # If no entry is found after (4), this method returns nil.
    #
    # Steps (3-4) are disabled when *friends* is false.
    def at?(name : Form, _visited = nil) : Entry?
      # (1-2) Traverse myself and my parents and flat-at
      # them for *name*.
      block = self
      while block
        block.flat_at?(name).try { |entry| return entry }
        block = block.parent?
      end

      # (3-4) Recurse on my delegates, and on my parent's delegates.
      block = self
      _visited ||= [] of Block
      while block
        unless block.in?(_visited)
          _visited << block
          block.each_friend do |friend|
            next if friend.in?(_visited)
            if entry = friend.at?(name, _visited)
              return entry
            end
          end
        end
        block = block.parent?
      end
    end

    # Returns the dictionary entry corresponding to *name*.
    # Does not traverse the block hierarchy.
    def flat_at?(name : Form) : Entry?
      dict.get(name) { }
    end

    # Returns whether this dictionary has an entry corresponding
    # to *name*.
    def has?(name : Form)
      !!at?(name)
    end

    # Returns the form at *index* in the tape. Dies if *index*
    # is out of bounds. See `Tape#at?`.
    def at(index : Int32) : Form
      tape.at?(index) || die("index out of bounds")
    end

    # Binds *name* to *entry* in this block's dictionary.
    def at(name : Form, entry : Entry) : self
      tap { dict.set(name, entry) }
    end

    # Dies: mutable keys disallowed.
    def at(name : Block, entry) : self
      die("mutable keys are disallowed, and block is mutable")
    end

    # Binds *name* to *form* in this block's dictionary.
    def at(name : Form, form : Form) : self
      at name, Entry.new(form)
    end

    # Makes an `OpenEntry` called *name* for *code* wrapped
    # in `Builtin`.
    def at(name : Word, desc = "a builtin", &code : Engine, Block ->) : self
      at name, OpenEntry.new Builtin.new(desc, code)
    end

    # :ditto:
    def at(name : String, desc = "a builtin", &code : Engine, Block ->) : self
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

    # Schedules this block for execution in *engine* using the
    # safe scheduling method (see `Engine#schedule`). Optionally,
    # a *stack* block may be provided (otherwise, the *engine*'s
    # current stack is used).
    def open(engine : Engine, stack : Block = engine.stack) : self
      tap { engine.schedule(self, stack) }
    end

    def val(engine : Engine? = nil, stack : Block? = nil)
      stack ||= Block.new
      engine ||= Engine.new
      engine.schedule(self, stack)
      engine.exhaust
      stack.drop
    end

    # Returns a shallow copy of this block.
    def shallow : Block
      self.class.new(parent: parent?, tape: tape.copy, dict: dict.copy, prototype: prototype)
    end

    # Replaces this block's tape with *other*'s.
    def resub(other : Block) : self
      self.tape = tape.resub(other.tape)
      self
    end

    # Loose equality: for two blocks to be loosely equal, their
    # tapes and their dictionaries must be loosely equal.
    #
    # Supports recursive (reflection) equality, e.g.:
    #
    # ```novika
    # [ ] $: a
    # a a shove
    # a first a = "=> true"
    # ```
    def ==(other)
      return false unless other.is_a?(self)
      return true if same?(other)
      return false unless count == other.count
      result = false
      executed = exec_recursive(:==) do
        result = tape == other.tape && dict == other.dict
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
    # this block's dictionary.
    private def assert?(engine : Engine, name : Form, type : T.class) : T? forall T
      entry = dict.get(name) { return }
      child = engine.child
      result = entry.val(child, Block.new.add(self))
      unless result.is_a?(Block) && same?(result)
        result.assert(child, T)
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
      when Color.class      then assert?(engine, AS_COLOR, type)
      when Boolean.class    then assert?(engine, AS_BOOLEAN, type)
      when QuotedWord.class then assert?(engine, AS_QUOTED_WORD, type)
      end || afail(T)
    end

    # Returns whether this block implements hook(s) needed
    # for behaving like *type*. See also: `assert(engine, type)`.
    def can_be?(type : T.class) forall T
      return true if is_a?(T)

      case T
      when Decimal.class    then dict.has?(AS_DECIMAL)
      when Quote.class      then dict.has?(AS_QUOTE)
      when Word.class       then dict.has?(AS_WORD)
      when Color.class      then dict.has?(AS_COLOR)
      when Boolean.class    then dict.has?(AS_BOOLEAN)
      when QuotedWord.class then dict.has?(AS_QUOTED_WORD)
      else
        false
      end
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

      unless dict.empty?
        io << " . "; ls.join(io, ' ')
      end

      io << " ]"
      io << "+" unless same?(prototype)
    end
  end
end
