module Novika
  # An engine object holds a reference to a block called the
  # *continuations block* (`conts`) (there is one continuations
  # block per one engine at all times).
  #
  # Engine objects are designed to `exhaust` this continuations
  # block, which means to bring its size to zero (it being longer
  # than zero at first, of course). This is done via evaluation.
  struct Engine
    include Form

    # Maximum amount of enabled continuations in `conts`. After
    # passing this number, `FormDied` is raised to bring attention
    # to such dangerous depth.
    #
    # NOTE: this number should be forgiving and probably settable
    # from the language.
    MAX_CONTS = 32_000

    # Maximum allowed engine nesting.
    MAX_ENGINE_NESTING = 1000

    # Index of the block in a continuation block.
    C_BLOCK_AT = 0

    # Index of the stack block in a continuation block.
    C_STACK_AT = 1

    # Returns the nesting number. Normally zero, for nested
    # engines increases with each nest. Allows us to sort of
    # "track" Crystal's call stack and stop nesting when it's
    # becoming dangerously deep.
    private getter nesting : Int32

    # Returns the continuations block (aka continuations stack).
    getter conts = Block.new

    def initialize
      @nesting = 0
    end

    protected def initialize(@nesting)
    end

    # Creates a conventional continuation `Block`.
    #
    # A conventional continuation block consists of two table
    # fields: one for the block, and one for the stack.
    def self.cont(block, stack)
      Block.new.add(block).add(stack)
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

    # Focal point for adding continuations. Returns self.
    #
    # The place where continuation stack's depth is tracked.
    def schedule(other : Block)
      if conts.count > MAX_CONTS
        raise Died.new("continuations stack dangerously deep (> #{MAX_CONTS})")
      end

      tap { conts.add(other) }
    end

    # Adds an instance of *form* block to the continuations
    # block, with *stack* set as the continuation stack.
    #
    # Returns self.
    def schedule(form : Block, stack)
      schedule Engine.cont(form.instance.to(0), stack)
    end

    # Adds an empty continuation with *stack* as set as the
    # continuation stack, and opens (normally pushes) *form*
    # there immediately.
    #
    # Returns self.
    def schedule(form, stack)
      # In case we're running in an empty engine, create an
      # empty block for the form.
      schedule Engine.cont(Block.new, stack)

      tap { form.open(self) }
    end

    # Exhausts all enabled continuations, starting from the
    # topmost (see `Block#top`) continuation in `conts`.
    def exhaust
      until conts.empty?
        begin
          while form = block.next?
            begin
              form.opened(self)
            rescue e : Died
              e.conts = conts.instance

              # Try to find a block with a death handler by reverse-
              # iterating through the continuations block.
              handler = nil
              until conts.empty?
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
          conts.drop
        rescue e : Died
          puts "ERROR IN THE INTERPRETER LOOP".colorize.yellow.bold
          raise EngineFailure.new(e)
        end
      end
    end

    # Enables *form* in this engine's offspring, with *stack*
    # set as the stack, and exhausts the offspring. Returns
    # *stack*. Exists to simplify calls to Novika from Crystal.
    # Raises if cannot nest (due to exceeding recursion depth,
    # see `MAX_ENGINE_NESTING`).
    def [](form, stack stack_ = stack)
      if nesting > MAX_ENGINE_NESTING
        raise Died.new(
          "too many engines (> #{MAX_ENGINE_NESTING}) of the same " \
          "origin: probably deep recursion in a word called from" \
          "native code, such as *asDecimal")
      end

      engine = Engine.new(nesting + 1)
      engine.schedule(form, stack_)
      engine.exhaust
      stack_
    end
  end
end
