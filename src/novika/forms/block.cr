module Novika
  # The regex that splits Novika source code into morphemes.
  MORPHEMES = /
      (?<num> [-+]?\d(?:[\d_]*\d)?(?:\.\d(?:[\d_]*\d)?)?) (?=\.|\s+|\[|\]|$)
    | (?<bb> \[)
    | (?<be> \])
    | (?<qword> \#[^"'\s\[\]]+)
    | (?<word> [^"'\s\.\[\]]+|\.)
    |'(?<quote> (?:[^'\\]|\\[\\ntrve'])*)'
    |"(?<comment> (?:[^"\\]|\\.)*)"
    |\s+
  /x

  # Regex that can be used to search for a pattern in `Block`
  # comments. Perfer `Form#effect` over matching by hand.
  EFFECT_PATTERN = /^(\(\s+(?:[^\(\)]*)\--(?:[^\(\)]*)\s+\)):/

  # Blocks are fundamental to Novika.
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
    property tape = Tape(Form).new

    # Returns the dictionary of this block.
    property dict : IDict = Dict.new

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

    # Creates and returns an orphan block with *array* being
    # its tape substrate's container. See `Tape.for`.
    def self.with(array : Array(Form))
      Block.new(tape: Tape.for(array))
    end

    # Creates and returns an orphan block whose tape will
    # contain *forms*.
    def self.[](*forms : Form)
      self.with(forms.map(&.as(Form)).to_a)
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
            .gsub(/(?<!\\)\\e/, '\e')
            .gsub(/\\\\/, '\\')
          block.add Quote.new(match)
        elsif match = $~["comment"]?
          if block.tape.empty?
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

      block.die("missing closing bracket") unless same?(block)

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

    # Explores this block's relatives, i.e., its vertical
    # (parent) and horizontal (friend) hierarchy neighbors,
    # calls *payload* with each such relative.
    #
    # When *payload* returns a value of type *T* (a non-nil),
    # exploration terminates. When *payload* returns nil,
    # exploration continues.
    #
    # The order is as follows, and is exactly Novika's *lookup order*.
    # Note that here, "yielded X" means "called *payload* with X".
    #
    # - First, this block is yielded.
    # - Then, the parent blocks of this block are yielded,
    #   starting from the immediate parent and ending with
    #   the toplevel (god) block.
    # - Then, this method recurses on friends of this block.
    # - Then, this method recurses on friends of parent blocks.
    #
    # *skip* can be used to disable exploration of specific
    # blocks, together with their (unexplored) vertical and
    # horizontal hierarchy.
    def each_relative(payload : Block -> T?, skip : Set(Block)? = nil) forall T
      return if skip && in?(skip)

      block = self
      while block
        break if skip && block.in?(skip)

        if value = payload.call(block)
          return value
        end

        block = block.parent?
      end

      block = self
      skip ||= Set(Block).new
      while block
        unless block.in?(skip)
          skip << block
          block.each_friend do |friend|
            return friend.each_relative(payload, skip) || next
          end
        end
        block = block.parent?
      end
    end

    # :ditto:
    def each_relative(skip = nil, &payload : Block -> T?) forall T
      each_relative(payload, skip)
    end

    # Returns the dictionary entry corresponding to *name*,
    # or dies. See `each_relative` for a detailed description
    # of lookup order.
    def at(name : Form, skip = nil) : Entry
      at?(name, skip) || die("undefined dictionary property: #{name}")
    end

    # Returns the dictionary entry corresponding to *name*,
    # or nil. See `each_relative` for a detailed description
    # of lookup order.
    def at?(name : Form, skip = nil) : Entry?
      each_relative skip, &.flat_at?(name)
    end

    # Returns whether this block can look up an entry corresponding
    # to *name*.
    def has?(name : Form, skip = nil)
      !!each_relative(skip) { |block| block.flat_has?(name) || nil }
    end

    # Returns the dictionary entry corresponding to *name*.
    # Does not traverse the block hierarchy.
    def flat_at?(name : Form) : Entry?
      dict.get(name) { }
    end

    # Returns whether this block's (and this block's only)
    # dictionary has an entry corresponding to *name*.
    def flat_has?(name : Form) : Bool
      dict.has?(name)
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
    def on_open(engine : Engine, stack : Block = engine.stack) : self
      tap { engine.schedule(self, stack) }
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

    # Returns whether the tape of this block includes *other*,
    # as per loose equality `==(other)`.
    def includes?(other : Form)
      tape.each { |form| return true if other == form }

      false
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
      #   === [ ⭮ ]
      #   >>> new
      #
      # ... should create a *copy* of `a`, then go thru its
      # child blocks depth first (`__tr` boards `instance`
      # to do that) and replace all reflections with the copy.
      #
      #   === [ ⭮ ]
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
    private def a?(name : Form, type : T.class) : T? forall T
      entry = dict.get(name) { return }
      result = Engine.exhaust(entry, Block.new.add(self)).top
      result.a(T) unless result.is_a?(Block) && same?(result)
    end

    # Converts this block into the given *type*. Code execution
    # may be required, hence the need for *engine*. If failed,
    # same as `Form#a`.
    def a(type : T.class) : T forall T
      return self if is_a?(T)

      case T
      when Decimal.class    then a?(AS_DECIMAL, type)
      when Quote.class      then a?(AS_QUOTE, type)
      when Word.class       then a?(AS_WORD, type)
      when Color.class      then a?(AS_COLOR, type)
      when Boolean.class    then a?(AS_BOOLEAN, type)
      when QuotedWord.class then a?(AS_QUOTED_WORD, type)
      end || afail(T)
    end

    # Returns whether this block implements hook(s) needed
    # for behaving like *type*. See also: `a(type)`.
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

    def to_quote : Quote
      a?(AS_QUOTE, Quote) || super
    end

    def effect(io)
      io << (prototype.comment? =~ EFFECT_PATTERN ? $1 : "a block")
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

    def to_s(io)
      if repr = a?(AS_QUOTE, Quote)
        # Block represents itself in some other way, respect
        # that here.
        io << repr.string
        return
      end

      executed = exec_recursive(:to_s) do
        io << "["
        unless tape.empty?
          (0...cursor).each { |index| io << " " << at(index) }
          unless cursor == count
            io << " |"
            (cursor...count).each { |index| io << " " << at(index) }
          end
        end
        unless dict.empty?
          io << " ·"
          dict.each do |name, entry|
            io << " " << (entry.is_a?(OpenEntry) ? "@" : "$") << "{" << name << " :: "
            entry.effect(io)
            io << "}"
          end
        end
        io << " ]"
      end

      io << "⭮" unless executed
    end
  end
end
