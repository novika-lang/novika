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

      omitted = Math.max(0, conts.count - MAX_TRACE)
      count = conts.count - omitted

      conts.each.skip(omitted).with_index do |cont_, index|
        cont_ = cont_.assert(Block)
        io << "  " << (index == count - 1 ? '└' : '├') << ' '
        io << "IN".colorize.bold << ' '
        cont_.at(C_BLOCK_AT).assert(Block).spotlight(io)
        io.puts

        io << "  " << (index == count - 1 ? ' ' : '│') << ' '
        io << "OVER".colorize.bold << ' ' << cont_.at(C_STACK_AT).assert(Block)
        io.puts
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
        while form = block.next?
          begin
            form.opened(self)
          rescue e : Form::Died
            if died = block.at?(Word::DIED)
              stack.add(Quote.new(e.details))
              begin
                died.open(self)
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
