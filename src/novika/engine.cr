module Novika
  module IExhaustTracker
    # Invoked before *engine* opens the given *form*.
    def on_form_begin(engine : Engine, form : Form)
    end

    # Invoked after *engine* opened the given *form*.
    def on_form_end(engine : Engine, form : Form)
    end
  end

  # An engine object is responsible for managing a *continuations block*.
  #
  # Continuations block consists of *continuatio**n** blocks*.
  #
  # Canonical continuation blocks themselves contain two blocks
  # (see `Engine.cont`):
  #
  # - *Code block*, more commonly known as simply the block
  #   (and as *active* block when its continuation is active,
  #    i.e., when it's being evaluated),
  #
  # - *Stack block*, more commonly known as simply the stack
  #   (and as *active* stack when its continuation is active,
  #    i.e., when it's being evaluated).
  #
  # `Engine#schedule` is used to create a continuation block
  # given a `Schedulable` object (usually a `Form`, and in rarer
  # cases an `Entry`) and a stack block. It then adds the
  # continuation block to the continuations block -- effectively
  # scheduling it for execution *on the next exhaust loop cycle*.
  #
  # Note that there are two other methods linked with execution
  # and implemented by all forms: `on_open`, and `on_parent_open`.
  # They *perform* whatever action the form wants rather than
  # simply *scheduling* it to be performed some time in the
  # future. Namely, `on_open` is invoked whenever the form at
  # hand is itself the target of opening (aka execution, aka
  # evaluation), and `on_parent_open` is invoked when a block
  # containing the form at hand (its parent block) is the target
  # of opening.
  #
  # An engine's *exhaust loop* is where most of the magic happens.
  # It is organized very much like the fetch-decode-execute cycle
  # in CPUs.
  #
  # For *fetch*, the engine finds the top (see `Block#top`)
  # continuation block, then finds the top form on the code
  # block, and invokes the `on_parent_open` method on it.
  #
  # This method is  analogous to *decoding* followed by *execution*.
  # The form is free to choose how it wants to make sense of itself,
  # given an engine. Some forms (e.g. words) end up scheduling
  # new continuation blocks `on_parent_open`, making the engine
  # go through them first.
  #
  # After the cursor of the active block hits the end, `Engine`
  # drops (see `Block#drop`) the continuation block (thereby
  # *closing* the code block).
  #
  # ```
  # caps = CapabilityCollection.with_default.enable_all
  # block = Block.new(caps.block).slurp("1 2 +")
  # stack = Block.new
  #
  # engine = Engine.new(caps)
  # engine.schedule(block, stack)
  # engine.exhaust
  #
  # puts stack # [ 3 ]
  #
  # # Or, shorter:
  #
  # caps = CapabilityCollection.with_default.enable_all
  # block = Block.new(caps.block).slurp("1 2 +")
  #
  # puts Engine.exhaust(caps, block) # [ 3 ]
  # ```
  class Engine
    # Maximum amount of scheduled continuations in `conts`. After
    # passing this number, `Error` is raised to bring attention
    # to such dangerous depth.
    MAX_CONTS = 1024

    # Maximum number of engines that can be created.
    #
    # This is for safety reasons only, particularly to prevent
    # infinite recursion in e.g. asserts which are called from
    # Crystal rather than Novika, thereby circumventing `MAX_CONTS`
    # checks. See `Engine.count`.
    MAX_ENGINES = 1024

    # Index of the code block in a continuation block.
    C_BLOCK_AT = 0

    # Index of the stack block in a continuation block.
    C_STACK_AT = 1

    # Holds an array of exhaust tracker objects associated with
    # all instances of `Engine`. These objects intercept forms
    # before/after opening in `Engine#exhaust`. This e.g. allows
    # frontends to analyze/track forms and/or matching blocks.
    class_getter trackers = [] of IExhaustTracker

    @@stack = [] of Engine

    # Returns the current engine. Raises a BUG exception if
    # there is no current engine.
    def self.current
      @@stack.last? || raise "BUG: there is no current engine"
    end

    # Pushes *engine* onto the engine stack.
    def self.push(engine : Engine) : Engine
      unless @@stack.size.in?(0..MAX_ENGINES)
        raise Error.new("bad engine stack depth: deep recursion in a __metaword__?")
      end

      @@stack << engine

      engine
    end

    # Pops *engine* from the engine stack. Raises a BUG exception
    # (and does not pop!) if the current engine is not *engine*
    # (or if it is absent).
    def self.pop(engine : Engine) : Engine?
      unless current.same?(engine)
        raise "BUG: lost track of the engine stack: unexpected engine on top!"
      end

      @@stack.pop
    end

    # Returns the capability collection used by this engine.
    getter capabilities : CapabilityCollection

    # Holds the continuations block (aka continuations stack).
    property conts = Block.new

    private def initialize(@capabilities : CapabilityCollection)
    end

    # Yields an instance of `Engine`.
    def self.new(capabilities : CapabilityCollection)
      engine = new(capabilities)

      Engine.push(engine)

      begin
        yield engine
      ensure
        Engine.pop(engine)
      end
    end

    # Creates and returns a canonical continuation block.
    #
    # A continuation block must include two blocks: the first is
    # called simply the *block* (found at `C_BLOCK_AT`), and the
    # second is called the *stack* block (found at `C_STACK_AT`).
    def self.cont(*, block, stack)
      Block[block, stack]
    end

    {% for name, schedule in {:exhaust => :schedule, :exhaust! => :schedule!} %}
      # Schedules *schedulable* and exhausts immediately. Returns the
      # resulting *stack* (creates one if `nil`).
      #
      # Useful for when you need the result of *schedulable*
      # immediately.
      #
      # For details see `Engine#{{schedule.id}}`.
      #
      # ```
      # caps = CapabilityCollection.with_default.enable_all
      # result = Engine.exhaust(caps, Block.new(caps.block).slurp("1 2 +"))
      # result.top # 3 : Novika::Decimal
      # ```
      def self.{{name.id}}(capabilities : CapabilityCollection, schedulable, stack = nil) : Block
        stack ||= Block.new
        Engine.new(capabilities) do |engine|
          engine.{{schedule.id}}(schedulable, stack)
          engine.exhaust
        end
        stack
      end
    {% end %}

    # Returns the active continuation.
    def cont
      conts.top.a(Block)
    end

    # Returns the block of the active continuation.
    def block
      cont.at(C_BLOCK_AT).a(Block)
    end

    # Returns the stack block of the active continuation.
    def stack
      cont.at(C_STACK_AT).a(Block)
    end

    # See `Form#die`.
    delegate :die, to: block

    # Main authorized point for adding continuations unsafely.
    # Returns self.
    #
    # Provides protection from continuations stack overflow.
    #
    # Adding to `conts` (the unauthorized way) does not protect
    # one from continuations stack overflow, and therefore from
    # a memory usage explosion.
    def schedule!(other : Block)
      if conts.count > MAX_CONTS
        die("recursion or block open is too deep (> #{MAX_CONTS})")
      end

      tap { conts.add(other) }
    end

    # Schedules a continuation with the given *block* and *stack*.
    def schedule!(*, block : Block, stack : Block)
      schedule! Engine.cont(block: block, stack: stack)
    end

    # See `Schedulable#schedule`.
    def schedule(schedulable : Schedulable, stack : Block)
      schedulable.schedule(self, stack)
    end

    # See `Schedulable#schedule!`.
    def schedule!(schedulable : Schedulable, stack : Block)
      schedulable.schedule!(self, stack)
    end

    # Converts value form of a death handler *entry* to a
    # block, if it's not a block already. Returns the block.
    private def entry_to_death_handler_block(entry : Entry) : Block
      unless form = entry.form.as?(Block)
        form = Block.new(block, prototype: block.prototype).add(entry.form)
      end
      form
    end

    # Returns the relevant death handler, or nil. Avoids
    # handlers whose prototype is *avoid_prototype*.
    #
    # To find the relevant death handler, the continuations
    # block is inspected right-to-left (back-to-front); each
    # code block is then asked to retrieve `Word::DIED`
    # using `Block#at?`. Regardless of the result, the
    # continuation block is then dropped.
    #
    # If succeeded in retrieving `Word::DIED`, converts the
    # resulting entry to block (does not distinguish between
    # openers and pushers). Returns that block.
    #
    # If all continuations were exhausted and no `Hook.died`
    # had been found, returns nil.
    def drop_until_death_handler?(avoid_prototype = nil)
      until conts.tape.empty?
        entry = block.entry_for?(Hook.died)
        conts.drop

        next unless entry

        handler = entry_to_death_handler_block(entry)
        unless avoid_prototype && handler.prototype.same?(avoid_prototype)
          return handler
        end
      end
    end

    def execute(form : Form)
      form.on_parent_open(self)
    rescue error : Error
      error.conts ||= conts.instance

      # Re-raise if no user-defined death handler ANYWHERE.
      # Death handler lookup is the broadest kind of lookup
      # in Novika, it traverses *all* running blocks and
      # their relatives.
      #
      # Avoid current block because that would case
      # infinite death loop.
      unless handler = drop_until_death_handler?(avoid_prototype: block.prototype)
        raise error
      end

      schedule(handler, stack: conts.count.zero? ? Block[error] : stack.add(error))
    end

    # Exhausts all scheduled continuations, starting from the
    # topmost (see `Block#top`) continuation in `conts`.
    def exhaust
      until conts.tape.empty?
        while form = block.next?
          Engine.trackers.each &.on_form_begin(self, form)
          execute(form)
          Engine.trackers.each &.on_form_end(self, form)
        end

        conts.drop
      end
    end
  end
end
