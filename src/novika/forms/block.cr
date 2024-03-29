module Novika
  # Regex that can be used to search for a pattern in `Block`
  # comments. Perfer `Form#effect` over matching by hand.
  EFFECT_PATTERN = /^(\(\s+(?:[^\(\)]*)\--(?:[^\(\)]*)\s+\)):/

  # A pool of `BlockIdMap` objects.
  #
  # You generally don't need to touch this.
  BlockMaps = ObjectPool(BlockIdMap).new(
    create: ->{ BlockIdMap.new },
    clear: ->(map : BlockIdMap) { map.clear }
  )

  # The amount of ignored parent blocks for circumventing heavy
  # lookup artillery: query self + P_IAMT parents first before
  # resorting to heavier graph exploration.
  #
  # Must be greater than 1.
  private P_IAMT = 8

  {% begin %}
    # :nodoc:
    record PIlist, {% for i in 1..P_IAMT %} v{{i}} : Block?, {% end %} do
      # Creates a new parent ignore list starting from *prev*.
      macro make(prev)
        PIlist.new(
          prev = \{{prev}}.parent?,
          {% for i in 2..P_IAMT %}
            prev &&= prev.parent?,
          {% end %}
        )
      end

      # Yields *v0* if it is not nil, followed by blocks in this
      # parent ignore list before the first nil block.
      def each(v0 = nil, &)
        yield v0 if v0

        {% for i in 1..P_IAMT %}
          yield (v{{i}} || return)
        {% end %}
      end

      # Returns whether to ignore the given *block*.
      def ignore?(block : Block) : Bool
        {% for i in 1..P_IAMT %}
          v{{i}}.same?(block) ||
        {% end %}

        false
      end
    end
  {% end %}

  # Executes a fetcher callback on every visited vertex in the block
  # graph starting from an entrypoint block, until the callback returns
  # `T`, or until there are no more blocks to explore.
  #
  # The quintessence of Novika, when looking up a *single* entry takes
  # a 70+ LoC object and a bunch of heap. Don't worry though; this is
  # the heavy artillery and it is not reached during simple lookup cases
  # (and most of Novika code consists of such simple cases).
  #
  # What is done here is a weird combination of DFS and BFS that also
  # tracks everything so as to not follow cyclic references forever.
  # All this complexity arose for historical reasons (a bunch of random
  # decisions, really) and simply for (the user's!) convenience.
  #
  # Parent-based lookup is a DFS under the hood, and friends lookup
  # is BFS-ish. And then all this recurses, and voilá! Don't break
  # your neck if you do choose to leap!
  struct EachRelativeFetch(T)
    def initialize(@fetcher : Block -> T?, @marked : BlockIdMap, @history : Block? = nil)
    end

    # Unconditionally pushes *block* to history if history is
    # enabled. Otherwise, a noop.
    private def try_push(block : Block)
      @history.try &.add(block)
    end

    # Unconditionally drops and returns a block from history
    # if history is enabled. Otherwise, a noop.
    private def try_pop
      @history.try &.drop
    end

    # Unconditionally drops all blocks before and including
    # *block* if history is enabled. Otherwise, a noop.
    private def try_pop(*, until block : Block)
      return unless history = @history

      until history.drop.as(Block).same?(block)
      end
    end

    # Pushes *block* to history if history is enabled and *toggle*
    # is true, then yields. If the block returns via `return`, *block*
    # is preserved in history (i.e. this is the expected behavior).
    # If the block ends executing nominally, *block* is dropped off
    # the history stack.
    #
    # If history is disabled, this method yields and is a noop.
    #
    # Returns whatever the block returned.
    private def try_push(block : Block, toggle = true, &)
      return yield unless history = @history
      return yield unless toggle

      history.add(block)
      temp = yield
      history.drop

      temp
    end

    # Returns the unique (ish) ID of *block*.
    #
    # Currently uses object id.
    private def id(block : Block) : UInt64
      block.object_id
    end

    # Returns whether *block* was already marked (seen, visited)
    # by this visitor.
    private def marked?(block : Block) : Bool
      @marked.has_key? id(block)
    end

    # Marks *block* as seen (visited) by this visitor.
    private def mark(block : Block)
      @marked[id(block)] = block
    end

    # If the fetcher returns a `T` given *block*, yields the `T`.
    # Otherwise, marks the block as seen (visited), and returns nil.
    private def fetch?(block : Block, push = false, & : -> T?) : T?
      # Early return (i.e. if block is marked already) is possible but
      # unwanted here, because it's going to be hit 1%-ish of the time
      # (believe me, won't you?!)
      #
      # This means that we'll be doing a somewhat expensive but totally
      # useless lookup 99% of the time. There's no point to.

      try_push(block, push) do
        next unless form = @fetcher.call(block)
        return yield form
      end

      mark(block)

      nil
    end

    # Yields parents of the given *block*. Does not follow cycles.
    #
    # *parents* should be an empty block id map. This map will be
    # populated with visited (parent) blocks after this method.
    private def each_parent(block : Block, parents : BlockIdMap, &)
      block = block.parent?

      while block
        id = id(block)

        # Break if block was visited already! Otherwise, we'll
        # loop endlessly.
        break if parents.has_key?(id)

        yield block

        parents[id], block = block, block.parent?
      end
    end

    # Yields the following blocks, and in the following order:
    #
    # - Yields parents of *block*.
    # - Yields friends of *block*.
    # - Yields friends of *block*'s parents.
    #
    # *adj* should be an empty block id map. This map will
    # be populated with all visited blocks after this method,
    # with the same order of entries as the order of yields.
    private def each_adjacent(block : Block, adj : BlockIdMap, &)
      firstp = nil
      lastp = nil

      #
      # Yield parents of block.
      #
      each_parent(block, adj) do |parent|
        firstp ||= parent

        # We have to add visited parents to history so that the
        # people who use it think it was a nested visit, in case
        # it was successful.
        try_push(parent)

        yield parent

        lastp = parent
      end

      try_pop(until: firstp) if firstp

      #
      # Yield friends of block.
      #
      block.each_friend do |friend|
        try_push(friend) { yield friend }

        adj[id(friend)] = friend
      end

      return unless firstp && lastp

      #
      # Yield friends of parents.
      #
      # Visited contains parents of block followed by friends
      # of block. We stop before the first friend of block.
      #
      adj.each_value do |parent|
        try_push(parent)

        parent.each_friend do |friend|
          try_push(friend) { yield friend }

          adj[id(friend)] = friend
        end

        break if parent.same?(lastp)
      end

      try_pop(until: firstp) if firstp

      nil
    end

    # Executes the fetcher callback on the first echelon of
    # *block*, and recurses on the second echelon.
    #
    # *push* is a toggle determining whether to push *block*
    # to history, if history is turned on.
    #
    # *p_ilist* is a list of immediately adjacent blocks
    # to ignore. See `PIlist` and `P_IAMT`.
    #
    # - The first echelon is parents and friends and friends
    #   of parents of *block*.
    #
    # - The second echelon is parents and friends and friends
    #   of parents of the first echelon. This method deeply
    #   recurses on the second echelon, effectively allowing
    #   lookup that is not limited in terms of depth.
    #
    # All this results in sometimes odd-*looking*, but generally
    # *correct* and even *expected* traversals of the graph.
    private def fetch_in_echelons?(block : Block, push = true, p_ilist : PIlist? = nil) : T?
      echelon1 = BlockMaps.acquire

      try_push(block, push) do
        #
        # 1ST ECHELON: ask parents and friends and friends
        # of parents.
        #
        each_adjacent(block, echelon1) do |adj|
          next if marked?(adj)
          next if p_ilist && p_ilist.ignore?(adj)

          fetch?(adj) { |form| return form }
        end

        echelon2 = BlockMaps.acquire

        #
        # 2ND ECHELON: **recurse** on parents and friends and
        # friends of parents of the 1ST ECHELON.
        #
        echelon1.each_value do |echelon1_block|
          try_push(echelon1_block) do
            each_adjacent(echelon1_block, echelon2) do |adj|
              next if marked?(adj)

              form = fetch?(adj) { |form| return form }
              form ||= fetch_in_echelons?(adj, push: false)

              return form if form
            end
          end

          echelon2.clear
        end
      ensure
        BlockMaps.release(echelon1)
        BlockMaps.release(echelon2) if echelon2
      end

      nil
    end

    # Executes the fetcher callback on every visited vertex in
    # the block graph starting from an *entrypoint* block, and
    # until the callback returns `T`, or until exhausted all
    # reachable vertices.
    def on(entrypoint : Block, ignore : Nil) : T?
      fetch?(entrypoint, push: true) { |form| return form }
      fetch_in_echelons?(entrypoint)
    end

    # Same as `on(entrypoint : Block, ignore : Nil)`, the difference
    # being that immediately adjacent block *ignore* list is taken
    # into account.
    #
    # Note that *entrypoint* is also ignored even though it is not
    # specified in the *ignore* list.
    def on(entrypoint : Block, ignore : PIlist) : T?
      fetch_in_echelons?(entrypoint, p_ilist: ignore)
    end
  end

  # Maps block unique identifiers (currently, object ids are used as
  # such) to blocks they identify.
  #
  # Used instead of Sets for forcing identity-based lookup rather
  # than hash-based lookup.
  alias BlockIdMap = Hash(UInt64, Block)

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
    include IReadableStore
    include ISubmittableStore

    # Maximum amount of forms to display in block string representation.
    MAX_COUNT_TO_S = 128

    # Maximum amount of forms to display in string representation
    # of *nested* blocks.
    MAX_NESTED_COUNT_TO_S = 12

    # Whether this block is a leaf. A block is a leaf when
    # it has no blocks in its tape.
    protected property? leaf = true

    # Returns the tape of this block.
    #
    # Tape is created on-demand. If possible, try to conform to this
    # checking `has_tape?` first.
    protected property tape : Tape(Form) { Tape(Form).new }

    # Returns whether this block has a tape.
    def has_tape? : Bool
      !!@tape
    end

    # Returns the dictionary of this block.
    #
    # Tape is created on-demand. If possible, try to conform to this
    # by checking `has_dict?` first.
    protected property dict : IDict { Dict.new }

    # Returns whether this block has a dict.
    def has_dict? : Bool
      !!@dict
    end

    # Holds this block's friends. Friends provide an alternative
    # lookup pathway: when parent hierarchy fails to find an entry
    # matching some name, friends are asked for that entry.
    #
    # Traversal and lookup is performed in reverse insertion order
    # (right to left). Therefore, MRO (i.e., its Novika counterpart)
    # is parent followed by friends, from the newest friend to the
    # oldest friend.
    protected getter friends : Block { Block.new }

    # Holds a reference to the parent block (them all in a
    # linked list of ancestors).
    property! parent : Block?

    # Returns the prototype of this block. Block instances return
    # their prototype (AST) blocks, AST blocks return themselves.
    property! prototype : Block

    # String comment of this block. It normally describes what
    # this block does.
    @comment : String?

    def initialize(@parent : Block? = nil, @prototype = self, @tape = nil, @dict = nil)
    end

    protected def initialize(*,
                             @parent : Block?,
                             @tape : Tape(Form)? = nil,
                             @dict = nil,
                             @prototype = self,
                             @leaf = true)
    end

    # Creates and returns an orphan block with *array* being
    # its tape substrate's container. See `Tape.for`.
    def self.with(array : Array(Form), leaf : Bool? = nil)
      new(
        parent: nil,
        tape: Tape.for(array),
        leaf: leaf.nil? ? array.includes?(Block) : leaf
      )
    end

    # Double-*form* optimized version of `Block.with`.
    def self.with(form1 : Form, form2 : Form)
      new(
        parent: nil,
        tape: Tape.for([form1, form2] of Form),
        leaf: !(form1.is_a?(Block) || form2.is_a?(Block))
      )
    end

    # Single-*form* optimized version of `Block.with`.
    def self.with(form : Form)
      new(
        parent: nil,
        tape: Tape.for([form] of Form),
        leaf: !form.is_a?(Block)
      )
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
      return unless comment = @comment
      return if comment.empty?

      comment
    end

    # Returns whether this block has a comment.
    def has_comment? : Bool
      !!comment?
    end

    # Sets the block comment of this block to *comment* in
    # case it doesn't have a comment already.
    #
    # Setting the comment can also be forced by making *force* true.
    def describe_with?(comment : String, force = false) : String?
      @comment = dedent comment if force || !comment?
    end

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
      classifier = Classifier.new(source, block: self)

      Scissors.cut(source) do |start, count, dot|
        classifier.classify(start, count, dot)
      end

      classifier.end

      self
    end

    # Returns the cursor position in this block.
    def cursor
      has_tape? ? tape.cursor : 0
    end

    # Returns the amount of forms in this block.
    def count
      has_tape? ? tape.count : 0
    end

    # Returns the amount of entries owned by (defined in) this block.
    def entry_count
      has_dict? ? dict.count : 0
    end

    # Yields all forms in this block, *going from left to right*.
    def each(&)
      return unless has_tape?

      tape.each { |form| yield form }
    end

    # Yields all forms in this block, *going from right to left*.
    def reverse_each(&)
      return unless has_tape?

      (0...tape.count).reverse_each do |index|
        yield tape.at!(index)
      end
    end

    # Returns the form at *index*, or nil.
    def at?(index)
      return unless has_tape?

      tape.at?(index)
    end

    # Returns the form at *index* in the tape. Dies if *index*
    # is out of bounds. See `Tape#at?`.
    def at(index : Int32) : Form
      die("index out of bounds") unless has_tape?

      tape.at?(index) || die("index out of bounds")
    end

    # Returns a block of forms between *b* and *e*, both
    # inclusive. Clamps *b* and *e* to bounds.
    def at(b : Int32, e : Int32)
      return Block.new unless has_tape?

      b = Math.max(b, 0)
      e = Math.min(e, count - 1)
      Block.with((b..e).map { |index| at(index) })
    end

    # Imports entries from *donor* to this block's dictionary
    # by mutating this block's dictionary.
    def import!(from donor : Block) : self
      dict.import!(donor.dict)

      self
    end

    # See `Tape#next?`.
    def next? : Form?
      return unless has_tape?

      self.tape, _ = tape.next? || return
    end

    # Moves tape cursor to *index*. Dies if *index* is out
    # of bounds. See `Tape#to?`.
    def to(index : Int32) : self
      return self if !has_tape? && index.zero?

      unless has_tape?
        die("cursor index out of bounds")
      end

      self.tape = tape.to?(index) || die("cursor index out of bounds")
      self
    end

    # Adds *form* after the cursor.
    def inject(form : Form) : self
      self.tape = tape.inject(form)
      self
    end

    # Drops and returns the form after the cursor. Dies if
    # cursor is at the end.
    def eject : Form
      die("eject out of bounds") unless has_tape?

      self.tape, _ = tape.eject? || die("eject out of bounds")
    end

    # Returns form after cursor, and moves cursor past it.
    #
    # Similar to `eject`, but doesn't modify the block.
    def thru : Form
      die("thru out of bounds") unless has_tape?

      self.tape, _ = tape.thru? || die("thru out of bounds")
    end

    # Adds *form* to the tape.
    def add(form : Form) : self
      impl = ->(other : Form) do
        self.leaf = false if other.is_a?(Block)
        self.tape = tape.add(other)
      end

      if hook = flat_at?(Hook.on_shove)
        default = Builtin.new("__shove__",
          desc: <<-END
          ( F -- ): default __shove__ implementation. Pushes Form to
           the block it was captured in.
          END
        ) { |_, stack| impl.call(stack.drop) }

        stack = Block.with(form, default)

        Engine.exhaust(Engine.current.capabilities, hook, stack)
      else
        impl.call(form)
      end

      self
    end

    # Mutably adds forms before the cursor in *forms* block's
    # tape after the cursor in this block's tape.
    def paste(forms : Block)
      return if forms.count.zero?

      self.tape = tape.paste(forms.tape)
    end

    # Returns the top form, dies if none.
    def top : Form
      die("no top for block") unless has_tape?

      top? || die("no top for block")
    end

    # Returns the top form, or nil if none.
    def top? : Form?
      tape.top?
    end

    # Duplicates the form before the cursor, dies if none.
    def dupe : self
      add(top)
    end

    # Swaps two forms before the cursor, dies if none.
    def swap : self
      self.tape = tape.swap? || die("at least two forms required before the cursor")
      self
    end

    # Slices this block at cursor. This results in two halves,
    # which are consequently returned.
    def slice : {Block, Block}
      return {Block.new(parent: self), Block.new(parent: self)} unless has_tape?

      lhs, rhs = tape.slice

      {Block.new(parent: self, tape: lhs),
       Block.new(parent: self, tape: rhs)}
    end

    # Removes and returns the top form. Dies if none.
    def drop : Form
      impl = ->do
        top.tap { self.tape = tape.drop? || raise "unreachable" }
      end

      if hook = flat_at?(Hook.on_cherry)
        default = Builtin.new("__cherry__",
          desc: "( -- ): default __cherry__ implementation."
        ) { impl.call }

        stack = Block.with(default)

        Engine.exhaust(Engine.current.capabilities, hook, stack).top
      else
        impl.call
      end
    end

    # Sorts this block's tape inplace, calls *cmp* comparator proc
    # for each form pair for a comparison integer -1, 0, or 1.
    def sort_using!(&cmp : Form, Form -> Int32) : self
      return self unless has_tape?

      self.tape = tape.sort_using!(cmp)
      self
    end

    # Returns whether this block has any friends.
    def has_friends? : Bool
      !!@friends && !friends.count.zero?
    end

    # Returns whether this block has a parent, friends, or both.
    def has_relatives? : Bool
      !!parent? || has_friends?
    end

    # Yields friends of this block. Asserts each is a block,
    # otherwise, dies (e.g. the user may have mistakenly
    # added some other form).
    def each_friend(&)
      return unless has_friends?

      friends.reverse_each do |friend|
        unless friend.is_a?(Block)
          die("expected a block, got #{friend.class.typedesc} for a friend")
        end
        yield friend
      end
    end

    # Adds *other* to the friendlist of this block.
    def befriend(other : Block) : self
      friends.add(other)

      self
    end

    # Removes *other* from the friendlist of this block.
    def unfriend(other : Block) : self
      return self unless has_friends?

      friends.delete_if { |friend| friend.is_a?(Block) && friend.same?(other) }

      self
    end

    # Explores this block's relatives, i.e., its vertical (parent) and
    # horizontal (friend) hierarchy, calls *fetcher* on each relative.
    # This process is also known as the exploration of the block graph,
    # where this block is the origin of exploration.
    #
    # If *fetcher* returns a value of type `T` (a non-nil) for the given
    # block, exploration terminates. If *fetcher* returns nil, exploration
    # continues.
    #
    # The order of exploration is roughly as follows:
    #
    # - The first echelon is explored: the parents, friends, and friends
    #   of parents of this block are explored.
    #
    # - The second echelon is explored: the parents, friends, and
    #   friends of parents of the blocks in first echelon are explored
    #   by recursing on each, effectively allowing lookup that is unlimited
    #   in terms of depth.
    #
    # *seen* can be used to disable exploration of specific blocks,
    # also blocking off the exploration of their relatives (if they
    # were not otherwise reached already).
    #
    # *skip_self* can be set to true to disable calling *fetcher* for
    # this block. Note that if this block is reached by other means
    # (e.g. as in `self -- other -- self`), *fetcher* is still going
    # to be called.
    #
    # *history*, a block, can optionally be provided. It will hold all
    # explored blocks leading to the "discovery" of `T`.
    def each_relative_fetch(
      fetcher : Block -> T?,
      seen : BlockIdMap? = nil,
      skip_self : Bool = false,
      history : Block? = nil
    ) : T? forall T
      return if skip_self && !has_relatives?

      # If history is enabled we're screwed with the fast paths.
      unless history
        #
        # This branch is taken 98% of the time when running
        # `novika tests`.
        #
        v0 = skip_self ? nil : self

        ilist = PIlist.make(self)
        ilist.each(v0) do |fastpath|
          next unless value = fetcher.call(fastpath)
          return value
        end
      end

      acquired = seen.nil?
      seen ||= BlockMaps.acquire

      begin
        fetch = EachRelativeFetch.new(fetcher, seen, history)
        fetch.on(self, ignore: ilist)
      ensure
        BlockMaps.release(seen) if acquired
      end
    end

    # :ditto:
    def each_relative_fetch(*args, **kwargs, &fetcher : Block -> T?) : T? forall T
      each_relative_fetch(fetcher, *args, **kwargs)
    end

    # Explores neighbor blocks of this block, calls *payload* with
    # each such neighbor block. Records all neighbors it visited in
    # *visited*.
    #
    # *Explicitly nested* (marked as *ExN1-2* in the diagram below)
    # neighbor blocks are blocks found in the dictionary and tape of
    # this block (marked as *B* in the diagram below).
    #
    # *Implicitly nested* (marked as *ImN1-4* in the diagram below)
    # neighbor blocks are blocks in the tapes and dictionaries of
    # explicitly nested neighbor blocks, and so on, recursively.
    #
    # ```text
    # ┌───────────────────────────────────────┐
    # │ B                                     │
    # │  ┌───────────────┐ ┌───────────────┐  │
    # │  │ ExN1          │ │ ExN2          │  │
    # │  │ ┌────┐ ┌────┐ │ │ ┌────┐ ┌────┐ │  │
    # │  │ │ImN1│ │ImN2│ │ │ │ImN3│ │ImN4│ │  │
    # │  │ └────┘ └────┘ │ │ └────┘ └────┘ │  │
    # │  │    ...    ... │ │    ...    ... │  │
    # │  └───────────────┘ └───────────────┘  │
    # │                                       │
    # └───────────────────────────────────────┘
    # ```
    def each_neighbor(payload : Block -> T?, visited : BlockIdMap? = nil) forall T
      # Iterate through the tape of this block. Recurse on every block
      # found there.
      each do |form|
        # I know this one and the one below are identical pieces of code,
        # but I refuse to factor them out!
        next unless form.is_a?(Block)
        next if visited.try &.has_key?(form.object_id)

        visited ||= BlockIdMap.new
        visited[form.object_id] = form

        return if payload.call(form)

        form.each_neighbor(payload, visited)
      end

      return unless has_dict?

      # Iterate through the dictionary of this block. Recurse on every block
      # value form there.
      dict.each do |_, entry|
        form = entry.form

        next unless form.is_a?(Block)
        next if visited.try &.has_key?(form.object_id)

        visited ||= BlockIdMap.new
        visited[form.object_id] = form

        return if payload.call(form)

        form.each_neighbor(payload, visited)
      end
    end

    # :ditto:
    def each_neighbor(visited : BlockIdMap? = nil, &payload : Block -> T?) forall T
      each_neighbor(payload, visited)
    end

    # Yields entry names and `Entry` objects from the dictionary
    # of this block.
    def each_entry(&)
      return unless has_dict?

      dict.each do |name, entry|
        yield name, entry
      end
    end

    # Yields entry name forms in this block's dictionary.
    def each_entry_name(&)
      each_entry do |name, _|
        yield name
      end
    end

    # Yields entry value forms in this block's dictionary.
    def each_entry_value(&)
      each_entry do |_, entry|
        yield entry.form
      end
    end

    # Returns a tuple that consists of the dictionary entry
    # corresponding to *name*, followed by the path block which
    # holds all blocks leading to the entry.
    #
    # Returns nil if *name* could not be found.
    #
    # In general works like `entry_for` and friends, the only
    # difference being that it also tracks and returns the path.
    # The latter makes this method slightly slower that `entry_for`.
    def path_to_entry?(name : Form) : {Entry, Block}?
      path = Block.new

      return unless entry = each_relative_fetch(history: path, &.flat_at?(name))

      {entry, path}
    end

    # Returns the dictionary entry for *name*, or dies.
    #
    # See `each_relative` for a detailed description of lookup
    # order etc.
    def entry_for(name : Form) : Entry
      entry_for?(name) || die("no value form for '#{name}'")
    end

    # Returns the dictionary entry for *name*, or nil.
    #
    # See `each_relative` for a detailed description of lookup
    # order etc.
    def entry_for?(name : Form) : Entry?
      if entry = flat_at?(name) # Fast path.
        return entry
      end

      each_relative_fetch(skip_self: true, &.flat_at?(name))
    end

    def has_form_for?(name : Form) : Bool
      !!each_relative_fetch { |block| block.flat_has?(name) || nil }
    end

    def form_for?(name : Form) : Form?
      entry_for?(name).try &.form
    end

    def submit?(name : Form, form : Form)
      entry_for?(name).try &.submit(form)
    end

    def opener?(name : Form) : Bool
      entry_for(name).opener?
    end

    def pusher?(name : Form) : Bool
      !opener?(name)
    end

    # Returns the dictionary entry corresponding to *name*.
    # Does not traverse the block hierarchy.
    def flat_at?(name : Form) : Entry?
      return unless has_dict?

      dict.get(name) { }
    end

    # Returns whether this block's (and this block's only)
    # dictionary has an entry corresponding to *name*.
    def flat_has?(name : Form) : Bool
      return false unless has_dict?

      dict.has?(name)
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
      at name, OpenEntry.new Builtin.new(name.id, desc, code)
    end

    # :ditto:
    def at(name : String, desc = "a builtin", &code : Engine, Block ->) : self
      at Word.new(name), Entry.new(Builtin.new(name, desc, code), opener: true)
    end

    # Yields forms from left to right until the block returns `true`
    # for one, then deletes that form. If the block does not return
    # `true` for any form, does nothing.
    def delete_if(& : Form -> Bool) : self
      index = nil

      each do |other|
        index ||= 0
        break if yield other
        index += 1
      end

      return self unless index

      delete_at(index)
    end

    # Deletes the form at *index*. Does nothing if index is out
    # of bounds.
    def delete_at(index : Int32) : self
      return self unless delpt = tape.to?(index + 1)
      return self unless delpt.drop?

      self.tape = tape.to?(Math.min(cursor, delpt.count)).not_nil!
      self
    end

    # Deletes the entry corresponding to *name* form from the
    # dictionary of this block if it exists there. Otherwise,
    # does nothing.
    def delete_entry(name : Form) : self
      dict.del(name)

      self
    end

    # Removes all owned dictionary entries in this block.
    def clear_entries : self
      dict.clear

      self
    end

    # Schedules this block for execution in *engine* using the
    # safe scheduling method (see `Engine#schedule`). Optionally,
    # a *stack* block may be provided (otherwise, the *engine*'s
    # current stack is used).
    def on_open(engine : Engine, stack : Block = engine.stack) : self
      engine.schedule(self, stack)

      self
    end

    # Schedules this block for execution, with *stack* set as the
    # stack that will be used by this block during execution.
    #
    # Moves the cursor before the first form so that the entire
    # block will be executed by *engine*.
    def schedule!(engine : Engine, stack : Block) : self
      return self if count.zero?

      engine.schedule!(stack: stack, block: to(0))

      self
    end

    # Schedules an instance of this block for execution, with *stack*
    # set as the stack that will be used by the instance during
    # execution.
    #
    # Moves the cursor of the instance before the first form
    # so that the entire block will be executed by *engine*.
    def schedule(engine : Engine, stack : Block) : self
      return self if count.zero?

      instance.schedule!(engine, stack)

      self
    end

    # Returns a shallow copy of this block.
    def shallow : Block
      self.class.new(parent: parent?,
        tape: has_tape? ? tape.copy : nil,
        dict: has_dict? ? dict.copy : nil,
        prototype: prototype
      )
    end

    # Replaces this block's tape with *other*'s.
    def resub(other : Block) : self
      self.tape = has_tape? ? tape.resub(other.tape) : Tape.new(other.tape.substrate)
      self
    end

    # Builds and returns a tape block for this block.
    #
    # Tape block is an *orphan* block whose tape is a shallow copy
    # of this block's tape; and whose dictionary is empty.
    def to_tape_block : Block
      Block.new(parent: nil, tape: has_tape? ? tape.copy : nil, leaf: leaf?)
    end

    # Builds and returns a dictionary block for this block.
    #
    # Dictionary block is an *orphan* block whose dictionary is a shallow
    # copy of this block's dictionary; and whose tape is empty.
    def to_dict_block : Block
      Block.new(parent: nil, dict: has_dict? ? dict.copy : nil)
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
    def ==(other) : Bool
      return false unless other.is_a?(self)
      return true if same?(other)
      return false unless count == other.count
      result = false
      executed = exec_recursive(:==) do
        result = true
        result &&= tape == other.tape if has_tape? || other.has_tape?
        result &&= dict == other.dict if has_dict? || other.has_dict?
      end
      executed && result
    end

    # Returns whether the tape of this block includes *other*,
    # as per loose equality `==(other)`.
    def includes?(other : Form) : Bool
      each { |form| return true if other == form }

      false
    end

    # Yields occurrences of the given *pattern* found in this
    # block. Matching is done using loose equality  `==(other)`.
    def each_occurrence_of(pattern : Form, &)
      index = 0
      each do |form|
        yield index if pattern == form
        index += 1
      end
    end

    # Creates and returns an instance of this block, under the
    # given *parent*.
    def instance(parent new_parent : Block = self, shallow = false, __tr : BlockIdMap? = nil) : Block
      copy = self.class.new(parent: new_parent,
        tape: has_tape? ? tape.copy : nil,
        prototype: prototype
      )

      return copy if leaf? || shallow

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
      __tr ||= BlockIdMap.new
      __tr[object_id] = copy

      # This is never reached with tape empty, so we don't care
      # whether we create it.
      copy.tape = copy.tape.map! do |form|
        next unless form.is_a?(Block)
        __tr[form.object_id]? || form.instance(same?(form.parent?) ? copy : form, __tr: __tr)
      end
      copy.leaf = false
      copy
    end

    # Assert through the result of running *name*'s value in
    # this block's dictionary.
    private def a?(name : Form, type : T.class, _depth = 0) : T? forall T
      if _depth > Engine::MAX_ENGINES
        # Engine itself tracks only vertical depth (nesting),
        # but we need to track cast depth.
        #
        # Give up when exceeded the max engine count.
        die("bad engine depth: deep recursion in a __metaword__?")
      end

      entry = flat_at?(name) || return
      stack = Block.with(self)
      result = Engine.exhaust(Engine.current.capabilities, entry, stack).top

      if result.is_a?(Block) && !same?(result)
        # Result is a different block. Increment depth to handle
        # deep (infinite) recursion properly.
        result.a(T, _depth + 1)
      elsif !result.is_a?(Block)
        result.a(T)
      end
    end

    # Converts this block into the given *type*. Code execution
    # may be required, hence the need for *engine*. If failed,
    # same as `Form#a`.
    def a(type : T.class, _depth = 0) : T forall T
      return self if is_a?(T)

      case T
      when Decimal.class    then a?(Hook.as_decimal, type, _depth)
      when Quote.class      then a?(Hook.as_quote, type, _depth)
      when Word.class       then a?(Hook.as_word, type, _depth)
      when Color.class      then a?(Hook.as_color, type, _depth)
      when Boolean.class    then a?(Hook.as_boolean, type, _depth)
      when QuotedWord.class then a?(Hook.as_quoted_word, type, _depth)
      when Byteslice.class  then a?(Hook.as_byteslice, type, _depth)
      end || afail(T)
    end

    # Returns whether this block implements hook(s) needed
    # for behaving like *type*. See also: `a(type)`.
    def can_be?(type : T.class) : Bool forall T
      return true if is_a?(T)

      case T
      when Decimal.class    then flat_has?(Hook.as_decimal)
      when Quote.class      then flat_has?(Hook.as_quote)
      when Word.class       then flat_has?(Hook.as_word)
      when Color.class      then flat_has?(Hook.as_color)
      when Boolean.class    then flat_has?(Hook.as_boolean)
      when QuotedWord.class then flat_has?(Hook.as_quoted_word)
      when Byteslice.class  then flat_has?(Hook.as_byteslice)
      else
        false
      end
    end

    def to_quote : Quote
      a?(Hook.as_quote, Quote) || super
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
    def spot(io, vicinity = 10, colorful = true)
      io << "["

      b = (cursor - vicinity).clamp(0..count - 1)
      e = (cursor + vicinity).clamp(0..count - 1)

      (b..e).each do |index|
        form = at(index)
        focus = index == cursor - 1

        Colorize.with.bold.toggle(focus && colorful).surround(io) do
          case form
          when Block then io << " […]"
          when Quote then io << " '…'"
          else
            io << " " << form
          end
        end

        io << " |".colorize.toggle(colorful).red if focus
      end

      io << " ]"
    end

    def to_s(io)
      if repr = a?(Hook.as_quote, Quote)
        # Block represents itself in some other way, respect
        # that here.
        io << repr.string
        return
      end

      executed = exec_recursive(:to_s) do
        io << "["
        if has_tape? && !tape.empty?
          (0...cursor).each { |index| io << " " << at(index) }
          unless cursor == count
            io << " |"
            (cursor...count).each { |index| io << " " << at(index) }
          end
        end
        if has_dict? && !dict.empty?
          io << " ·"
          dict.each do |name, entry|
            io << " " << (entry.opener? ? "@" : "$") << "{" << name << " :: "
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
