module Novika
  # Words open entries they're assigned to in the dictionary
  # of their enclosing block.
  struct Word
    include Form

    # Returns the underlying string id.
    getter id : String

    def initialize(@id)
    end

    def desc(io : IO)
      io << "word named '" << id << "'"
    end

    def self.typedesc
      "word"
    end

    def private?
      id.prefixed_by?('_')
    end

    def on_parent_open(engine : Engine) : self
      if entry = engine.block.entry_for?(self)
        # An entry exists for this word in the current block
        # or in its parents.
        entry.on_open(engine)
        return self
      end

      block = current = engine.block

      while block && (trap = block.entry_for?(Hook.trap))
        # A trap entry exists for this word in *block*. Traps are
        # inherited as opposed to conversion words like __decimal__.
        form = trap.form

        if form.is_a?(Block) && form.prototype.same?(current.prototype)
          # If the trap we've found is the same one as this
          # block, or block is an instance of the trap block,
          # then this will recurse infinitely. Go search for
          # the trap in the block above *block* (its parent).
          block = block.parent?
          next
        end

        engine.stack.add Word.new(id)
        trap.on_open(engine)

        return self
      end

      # No entry and no valid trap: err out.
      die("definition for #{self} not found in the enclosing block(s)")

      self
    end

    def to_s(io)
      io << "#" if id.in?("true", "false")
      io << id
    end

    def_equals_and_hash id
  end

  # Quoted words are words prefixed by '#': e.g., `#foo`. It
  # lets you 'coat' a word: `#foo open` is the same as `foo`,
  # `##foo open` is the same as `#foo`, etc. Levels of coating
  # are peeled off like in an onion.
  struct QuotedWord
    include Form
    include ShouldOpenWhenScheduled

    # Returns the underlying string id.
    getter id : String

    def initialize(@id)
    end

    def desc(io : IO)
      io << "quoted word '" << id << "'"
    end

    def self.typedesc
      "quoted word"
    end

    # "Peels" off a layer of quoting.
    #
    # ```
    # QuotedWord.new("#foo").peel   # Word.new("foo")
    # QuotedWord.new("##foo").peel  # QuotedWord.new("#foo")
    # QuotedWord.new("###foo").peel # QuotedWord.new("##foo")
    # ```
    def peel
      id.prefixed_by?('#') ? QuotedWord.new(id.lchop) : Word.new(id)
    end

    # Converts this quoted word to `Word`.
    def to_word : Word
      Word.new(id.lstrip('#'))
    end

    def on_parent_open(engine) : self
      tap { peel.onto(engine.stack) }
    end

    def to_s(io)
      io << '#' << id
    end

    def_equals_and_hash id
  end
end
