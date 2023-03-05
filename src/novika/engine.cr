module Novika
  # An engine object is responsible for managing its own
  # *continuations block*.
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
  # from a `Form` and a stack block, and then add it to the
  # continuations block.
  #
  # If form is a block, `Engine#schedule` will instantiate
  # it and use the instance, moving the instance's cursor
  # to 0 (meaning before the first form, if any).
  #
  # `Engine#schedule!` is similar to `Engine#schedule`, with
  # the only exception being that it doesn't create an instance
  # if form is a block, but instead uses the block as-is.
  #
  # Once all is set up, one can exhaust the engine. `Engine#exhaust`
  # finds the top (see `Block#top`) continuation block, slides
  # its code block's cursor to the right until the end, and
  # calls `Form#on_parent_open` on every form, passing itself
  # as the argument (letting the form decide what to do next).
  #
  # After the cursor hits the block's end, `Engine` drops
  # (see `Block#drop`) the continuation block (thereby *closing*
  # the code block).
  #
  # Some forms (e.g. words) may end up scheduling continuation blocks
  # `on_parent_open`, making the engine go through them first.
  #
  # Successful calls to `Engine#exhaust` leave the continuations
  # block empty. This is why the method is called "exhaust".
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

    # Capability collection used by default.
    DEFAULT_CAPS = CapabilityCollection.with_default.enable_all

    @@stack = [] of Engine

    # Returns the current engine. Raises a BUG exception if
    # there is no current engine.
    def self.current
      @@stack.last? || raise "BUG: there is no current engine"
    end

    # Pushes *engine* onto the engine stack.
    def self.push(engine : Engine) : Engine
      unless @@stack.size.in?(0..MAX_ENGINES)
        raise Error.new("bad engine stack depth: maybe deep recursion in *as...?")
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
    # A continuation block must include two blocks: the first
    # is called the *code* block (found at `C_BLOCK_AT`), the
    # second is called the *stack* block (found at `C_STACK_AT`).
    def self.cont(code, stack)
      Block[code, stack]
    end

    # Schedules and executes *form* immediately. Returns the
    # resulting *stack* (creates one if `nil`).
    #
    # See `Engine#schedule!` for information on how *form*
    # is evaluated.
    #
    # Useful for when you need the result of *form* immediately,
    # especially from Crystal.
    def self.exhaust!(
      capabilities : CapabilityCollection,
      form,
      stack = nil
    ) : Block
      stack ||= Block.new
      Engine.new(capabilities) do |engine|
        engine.schedule!(form, stack)
        engine.exhaust
      end
      stack
    end

    # :ditto:
    def self.exhaust!(
      capabilities : CapabilityCollection,
      entry : OpenEntry,
      stack = nil
    ) : Block
      exhaust!(capabilities, entry.form, stack)
    end

    # :ditto:
    def self.exhaust!(
      capabilities : CapabilityCollection,
      entry : Entry,
      stack = nil
    ) : Block
      stack ||= Block.new
      entry.onto(stack)
      stack
    end

    # Schedules and executes *form* immediately. Returns the
    # resulting *stack* (creates one if `nil`).
    #
    # See `Engine#schedule` for information on how *form*
    # is evaluated.
    #
    # Useful for when you need the result of *form* immediately,
    # especially from Crystal.
    def self.exhaust(
      capabilities : CapabilityCollection,
      form,
      stack = nil
    ) : Block
      stack ||= Block.new
      Engine.new(capabilities) do |engine|
        engine.schedule(form, stack)
        engine.exhaust
      end
      stack
    end

    # :ditto:
    def self.exhaust(
      capabilities : CapabilityCollection,
      form entry : OpenEntry,
      stack = nil
    ) : Block
      exhaust(capabilities, entry.form, stack)
    end

    # :ditto:
    def self.exhaust(
      capabilities : CapabilityCollection,
      form entry : Entry,
      stack = nil
    ) : Block
      exhaust!(capabilities, entry, stack)
    end

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

    # Focal authorized point for adding continuations unsafely.
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

    # Unsafe `schedule`. Use `schedule` unless you have instantiated
    # *form* yourself, or you know what you're doing.
    #
    # See `schedule(form : Block, stack)`.
    def schedule!(form : Block, stack)
      return if form.count.zero?

      schedule! Engine.cont(form.to(0), stack)
    end

    # Schedules *form* for opening in *stack*.
    #
    # Same as `schedule(form, stack)`.
    def schedule!(form : Builtin | QuotedWord | Library | ForeignFunction | Hole, stack)
      unless stack.same?(self.stack)
        # Schedule a fictious entry. Note how we do *not* set
        # the cursor to 0. This handles two things:
        #
        # 1) First, the engine won't try to execute *form*
        #    again on the next interpreter loop cycle.
        #
        # 2) Second, if *form* schedules something else, all
        #    will work as expected: first, the scheduled thing
        #    will run, and then all that's above, again, without
        #    re-running *form* because the cursor is past it.
        schedule! Engine.cont(Block.new.add(form), stack)
      end

      form.on_open(self)
    end

    # Same as `schedule(form, stack)`.
    def schedule!(form, stack)
      form.onto(stack)
    end

    # Adds an instance of *form* block to the continuations
    # block, with *stack* set as the continuation stack.
    #
    # Returns self.
    def schedule(form : Block, stack)
      return if form.count.zero?

      schedule!(form.instance, stack)
    end

    # Adds an empty continuation with *stack* as set as the
    # continuation stack, and opens (normally pushes) *form*
    # there immediately.
    #
    # Returns self.
    def schedule(form, stack)
      schedule!(form, stack)
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
    # If all continuations were exhausted and no `Word::DIED`
    # had been found, returns nil.
    def drop_until_death_handler?(avoid_prototype = nil)
      until conts.tape.empty?
        entry = block.entry_for?(Word::DIED)
        conts.drop

        next unless entry

        handler = entry_to_death_handler_block(entry)
        unless avoid_prototype && handler.prototype.same?(avoid_prototype)
          return handler
        end
      end
    end

    # Exhausts all scheduled continuations, starting from the
    # topmost (see `Block#top`) continuation in `conts`.
    def exhaust
      until conts.tape.empty?
        while form = block.next?
          begin
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

            # Errors are also forms. They are rarely seen
            # and used as such, but they are.
            schedule(handler, conts.count.zero? ? Block[error] : stack.add(error))
          end
        end

        conts.drop
      end
    end
  end
end
