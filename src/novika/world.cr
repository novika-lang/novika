module Novika
  # Novika interpreter and context.
  struct World
    include Form

    # Maximum amount of trace entries in error reports. After
    # passing this number, only `MAX_TRACE` *last* entries
    # will be displayed.
    MAX_TRACE = 64

    # Maximum amount of enabled continuations in `conts`. After
    # passing this number, `FormDied` is raised to bring attention
    # to such dangerous depth.
    #
    # NOTE: this number should be forgiving and probably settable
    # from the language.
    MAX_CONTS = 32_000

    # Maximum allowed world nesting. Used, for instance, to
    # prevent very deep recursion in `World::ENQUOTE` et al.
    MAX_WORLD_NESTING = 1000

    # Index of the block in a continuation block.
    C_BLOCK_AT = 0

    # Index of the stack block in a continuation block.
    C_STACK_AT = 1

    # Returns the nesting number. Normally zero, for nested
    # worlds increases with each nest. Allows us to sort of
    # "track" Crystal's call stack and stop nesting when it's
    # becomes dangerously deep.
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
      Block.new
        .add(block)
        .add(stack)
    end

    # Returns the active continuation.
    def cont
      conts.top.assert(Block)
    end

    # Returns the block of the active continuation.
    def block
      cont.at(C_BLOCK_AT).assert(Block)
    end

    # Returns the stack block of the active continuation.
    def stack
      cont.at(C_STACK_AT).assert(Block)
    end

    # Reports about an *error* into *io*.
    def report(e : Form::Died, io = STDOUT)
      io << "Sorry: ".colorize.red.bold << e.details << "."
      io.puts
      io.puts

      # Conserved conts.
      return unless cconts = e.conts

      omitted = Math.max(0, cconts.count - MAX_TRACE)
      count = cconts.count - omitted

      cconts.each.skip(omitted).with_index do |cont_, index|
        if cont_.is_a?(Block)
          io << "  " << (index == count - 1 ? '└' : '├') << ' '
          io << "IN".colorize.bold << ' '
          cblock = cont_.at?(C_BLOCK_AT)
          cblock.is_a?(Block) ? cblock.spotlight(io) : io << (cblock || "[invalid continuation block]")
          io.puts

          io << "  " << (index == count - 1 ? ' ' : '│') << ' '
          io << "OVER".colorize.bold << ' ' << (cont_.at?(C_STACK_AT) || "[invalid continuation stack]")
          io.puts
        else
          io << "INVALID CONTINUATION".colorize.red.bold
        end
      end

      io.puts
    end

    # Focal point for adding continuations. Returns self.
    #
    # The place where continuation stack's depth is tracked.
    def enable(other : Block)
      if conts.count > MAX_CONTS
        raise Form::Died.new("continuations stack dangerously deep (> #{MAX_CONTS})")
      end

      tap { conts.add(other) }
    end

    # Adds an instance of *form* block to the continuations
    # block, with *stack* set as the continuation stack.
    #
    # Returns self.
    def enable(form : Block, stack)
      enable World.cont(form.instance.to(0), stack)
    end

    # Adds an empty continuation with *stack* as set as the
    # continuation stack, and opens (normally pushes) *form*
    # there immediately.
    #
    # Returns self.
    def enable(form, stack)
      # In case we're running in an empty world, create an
      # empty block for the form.
      enable World.cont(conts.empty? ? Block.new : block, stack)

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
            rescue e : Form::Died
              e.conts = conts.instance

              # Try to find a block with a death handler by
              # reverse-iterating through the continuations
              # block.
              handler = nil
              until conts.empty?
                break if handler = block.at?(Word::DIED)
                conts.drop
              end

              if handler
                stack.add(e)
                begin
                  handler.open(self)
                  next
                rescue e : Form::Died
                  puts "DEATH HANDLER DIED".colorize.yellow.bold
                end
              end

              report(e)
              abort("Sorry! Exiting because of this error.")
            end
          end
          conts.drop
        rescue e : Form::Died
          puts "ERROR IN THE INTERPRETER LOOP".colorize.yellow.bold
          report(e)
          abort("Cannot continue!")
        end
      end
    end

    # Enables *form* in this world's offspring, with *stack*
    # set as the stack, and exhausts the offspring. Returns
    # *stack*. Exists to simplify calls to Novika from Crystal.
    # Raises if cannot nest (due to exceeding recursion depth,
    # see `MAX_WORLD_NESTING`).
    def [](form, stack stack_ = stack)
      if nesting > MAX_WORLD_NESTING
        raise Form::Died.new(
          "too many worlds (> #{MAX_WORLD_NESTING}) of the same " \
          "origin world:probably deep recursion in a word called " \
          "from native code, such as #{Word::ENQUOTE}")
      end

      world = World.new(nesting + 1)
      world.enable(form, stack_)
      world.exhaust
      stack_
    end
  end
end
