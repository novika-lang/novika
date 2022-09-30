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

  # An engine object holds a reference to a block called the
  # *continuations block* (`conts`) (there is one continuations
  # block per one engine at all times).
  #
  # Engine objects are designed to `exhaust` this continuations
  # block, which means to bring its size to zero (it being longer
  # than zero at first, of course). This is done via evaluation
  # (which is mostly known as *opening* in Novika).
  #
  # Forms decide how they want to be opened by implementing
  # `Form#open`/`Form#opened`, which accepts an instance of
  # Engine. The default approach for opening a form is to
  # push it onto the active stack. Forms like `Word`s use
  # `schedule` to schedule blocks for evaluation. When the
  # `opened` call finishes, Engine will start to execute the
  # last scheduled block (last scheduled continuation) and
  # so on, up until there are no scheduled blocks
  # (continuations) left.
  struct Engine
    # Maximum amount of scheduled continuations in `conts`. After
    # passing this number, `Died` is raised to bring attention
    # to such dangerous depth.
    MAX_CONTS = 1024

    # Maximum allowed engine nesting.
    MAX_ENGINE_NESTING = 1024

    # Index of the code block in a continuation block.
    C_BLOCK_AT = 0

    # Index of the stack block in a continuation block.
    C_STACK_AT = 1

    # Returns the nesting number. Normally zero, for nested
    # engines increases with each nest. Allows us to sort of
    # "track" Crystal's call stack and stop nesting when it's
    # becoming dangerously deep.
    private getter nesting : Int32

    # A mapping of blocks to their IDs. Nil if profiling is disabled.
    getter! bids : Hash(Block, Int32)?

    # A mapping of block IDs to their `Stat` objects. Nil if
    # profiling is disabled.
    getter! prof : Hash(Int32, Stat)?

    # Returns the continuations block (aka continuations stack).
    getter conts = Block.new

    # Creates a new engine.
    #
    # *profile* can be set to `true` to enable profiling. Collecting
    # profiling data makes Engine slower (sometimes a lot), but it
    # will allow you to analyze the resulting `prof` `Stat`s which
    # are fairly detailed. See `Stat`.
    def initialize(profile = false)
      initialize(0, profile)
    end

    protected def initialize(@nesting, @profile : Bool)
      if profile
        @bids = {} of Block => Int32
        @prof = {} of Int32 => Stat
      end
    end

    # Creates a conventional continuation `Block`.
    #
    # A conventional continuation block consists of two blocks:
    # a code block (aka simply the block), and a stack block
    # (aka simply the stack).
    def self.cont(block, stack)
      Block.new.add(block).add(stack)
    end

    # Creates and returns an offspring engine. Use this if
    # you want stack overflow handling instead of segfault.
    #
    # There are no speed implications, the only inconvenience
    # is the need to have a parent engine to begin with.
    def child
      nesting = @nesting + 1

      if nesting > MAX_ENGINE_NESTING
        raise Died.new("recursion or block open is too deep (> #{MAX_ENGINE_NESTING})")
      end

      Engine.new(nesting, @profile)
    end

    # Returns the active continuation.
    def cont
      conts.top.assert(self, Block)
    end

    # Returns the block of the active continuation.
    def block
      cont.at(C_BLOCK_AT).assert(self, Block)
    end

    # Returns the stack block of the active continuation.
    def stack
      cont.at(C_STACK_AT).assert(self, Block)
    end

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
        raise Died.new("recursion or block open is too deep (> #{MAX_CONTS})")
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

      form.open(self)
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

    # Exhausts all scheduled continuations, starting from the
    # topmost (see `Block#top`) continuation in `conts`.
    def exhaust
      until conts.count.zero?
        begin
          while form = (scheduler = block).next?
            begin
              form.opened(self)
              if @profile
                schproto = scheduler.prototype
                scheeproto = block.prototype
                next if schproto.same?(scheeproto)

                start_prof_for(form, scheeproto, scheduled_by: schproto)
              end
            rescue e : Died
              e.conts = conts.instance

              # Try to find a block with a death handler by reverse-
              # iterating through the continuations block.
              handler = nil
              until conts.count.zero?
                handler = block.at?(Word::DIED)
                conts.drop
                break if handler
              end

              if handler
                stack.add(e)
                begin
                  handler.open(self)
                  next
                rescue e : Died
                  puts "DEATH HANDLER DIED".colorize.yellow.bold
                end
              end
              raise EngineFailure.new(e)
            end
          end

          next conts.drop unless @profile

          dropped_cont = conts.drop.as(Block)
          dropped_cont_block = dropped_cont.at(C_BLOCK_AT).as(Block)
          end_prof_for(dropped_cont_block.prototype)
        rescue e : Died
          puts "ERROR IN THE INTERPRETER LOOP".colorize.yellow.bold
          raise EngineFailure.new(e)
        end
      end
    end
  end
end
