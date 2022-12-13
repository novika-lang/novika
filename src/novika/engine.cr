module Novika
  # Block statistic object.
  class Stat
    record SchedStat, scheduler : Int32, count : Int32, cumul : Time::Span? = nil

    # Holds the unique identifier of the block.
    property id : Int32

    # Holds the block.
    property block : Block

    # Holds the words that scheduled this block (speculative,
    # as Novika has no sure way to associate words and blocks).
    property words = Set(Word).new

    # Holds block IDs that scheduled this block mapped to a
    # more detailed `SchedStat`.
    property scheduled_by = {} of Int32 => SchedStat

    # Clock stack used to record how much time block spent
    # in its schedulers.
    property clocks = [] of {Int32, Time::Span}

    def initialize(@id, @block)
    end
  end

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
  # bundle = Bundle.with_default.enable_all
  # block = Block.new(bundle.bb).slurp("1 2 +")
  # stack = Block.new
  #
  # engine = Engine.new(bundle)
  # engine.schedule(block, stack)
  # engine.exhaust
  #
  # puts stack # [ 3 ]
  #
  # # Or, shorter:
  #
  # bundle = Bundle.with_default.enable_all
  # block = Block.new(bundle.bb).slurp("1 2 +")
  #
  # puts Engine.exhaust(block, bundle: bundle) # [ 3 ]
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

    # Holds the amount of living Engines. When an `Engine` is
    # created, this number is increased. When an `Engine` is
    # collected by the GC (finalized), this number is decreased.
    class_getter count = 0

    # :ditto:
    protected def self.count=(other)
      unless other.in?(0..MAX_ENGINES)
        raise Error.new("bad engine count: maybe deep recursion in *as...?")
      end
      @@count = other
    end

    # Returns the feature bundle this engine is running over.
    getter bundle : Bundle

    # Maps blocks to their IDs. Nil if profiling is disabled.
    getter! bids : Hash(Block, Int32)?

    # Maps block IDs to `Stat` objects. Nil if profiling is disabled.
    getter! prof : Hash(Int32, Stat)?

    # Holds the continuations block (aka continuations stack).
    property conts = Block.new

    # Creates an engine.
    #
    # *profile* can be set to `true` to enable profiling. Collecting
    # profiling data makes Engine slower (sometimes a lot), but it
    # will allow you to analyze the resulting `prof` `Stat`s which
    # are fairly detailed. See `Stat`.
    def initialize(@bundle : Bundle, @profile = false)
      Engine.count += 1

      if profile
        @bids = {} of Block => Int32
        @prof = {} of Int32 => Stat
      end
    end

    def finalize
      Engine.count -= 1
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
    def self.exhaust!(form, stack = nil, bundle = Bundle.with_default) : Block
      stack ||= Block.new
      engine = Engine.new(bundle)
      engine.schedule!(form, stack)
      engine.exhaust
      stack
    end

    # :ditto:
    def self.exhaust!(entry : OpenEntry, stack = nil, bundle = Bundle.with_default) : Block
      exhaust!(entry.form, stack, bundle)
    end

    # :ditto:
    def self.exhaust!(entry : Entry, stack = nil, bundle = nil) : Block
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
    def self.exhaust(form, stack = nil, bundle = Bundle.with_default) : Block
      stack ||= Block.new
      engine = Engine.new(bundle)
      engine.schedule(form, stack)
      engine.exhaust
      stack
    end

    # :ditto:
    def self.exhaust(form entry : OpenEntry, stack = nil, bundle = Bundle.with_default) : Block
      exhaust(entry.form, stack, bundle)
    end

    # :ditto:
    def self.exhaust(form entry : Entry, stack = nil, bundle = Bundle.with_default) : Block
      exhaust!(entry, stack, bundle)
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
      schedule! Engine.cont(form.to(0), stack)
    end

    # Schedules *form* for opening in *stack*.
    #
    # Same as `schedule(form, stack)`.
    def schedule!(form : Builtin | QuotedWord, stack)
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

    # Starts profiling for *schedulee*.
    private def start_prof_for(pseudonym, schedulee, scheduled_by scheduler)
      bids.rehash # Repair block ID hash, blocks may have changed.

      # Fetch or generate an ID for the scheduler block.
      scheduler_id = bids.fetch(scheduler) do
        bids[scheduler] = bids.last_value?.try &.+(1) || 0
      end

      # Fetch or generate an ID for the schedulee block.
      schedulee_id = bids.fetch(schedulee) do
        bids[schedulee] = bids.last_value?.try &.+(1) || 0
      end

      # Fetch or create an entry for the schedulee block.
      stat = prof.fetch(schedulee_id) do
        prof[schedulee_id] = Stat.new(schedulee_id, schedulee)
      end

      # Fetch the individual scheduler statistic record,
      # or create a new one.
      sched_stat =
        stat.scheduled_by[scheduler_id]? ||
          Stat::SchedStat.new(scheduler_id, 0)

      stat.words << pseudonym if pseudonym.is_a?(Word)
      stat.scheduled_by[scheduler_id] = sched_stat.copy_with(count: sched_stat.count + 1)
      stat.clocks << {scheduler_id, Time.monotonic}
    end

    # Ends profiling for *schedulee*.
    private def end_prof_for(schedulee)
      endtime = Time.monotonic

      bids.rehash # Repair block ID hash, blocks may have changed.

      return unless schedulee_id = bids[schedulee]?
      return unless stat = prof[schedulee_id]?

      scheduler_id, starttime = stat.clocks.pop? || return

      stat.scheduled_by[scheduler_id] = stat
        .scheduled_by[scheduler_id]
        .copy_with(cumul: endtime - starttime)
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
    # To find the relevant death handler, The continuations
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
    def dig_for_death_handler?(avoid_prototype = nil)
      until conts.tape.empty?
        entry = block.at?(Word::DIED)
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
        while form = (scheduler = block).next?
          begin
            form.on_parent_open(self)
            if @profile
              schproto = scheduler.prototype
              scheeproto = block.prototype
              next if schproto.same?(scheeproto)

              start_prof_for(form, scheeproto, scheduled_by: schproto)
            end
          rescue error : Error
            error.conts = conts.instance

            # Re-raise if no user-defined death handler ANYWHERE.
            # Death handler lookup is the broadest kind of lookup
            # in Novika, it traverses *all* running blocks and
            # their relatives.
            #
            # Avoid current block because that would case
            # infinite death loop.
            unless handler = dig_for_death_handler?(avoid_prototype: block.prototype)
              raise error
            end

            # Errors are also forms. They are rarely seen
            # and used as such, but they are.
            schedule(handler, conts.count.zero? ? Block[error] : stack.add(error))
          end
        end

        next conts.drop unless @profile

        dropped_cont = conts.drop.as(Block)
        dropped_cont_block = dropped_cont.at(C_BLOCK_AT).as(Block)
        end_prof_for(dropped_cont_block.prototype)
      end
    end
  end
end
