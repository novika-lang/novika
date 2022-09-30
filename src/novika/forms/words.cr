class String
  # Returns whether this string starts with *prefix* but also
  # has other characters after it.
  def prefixed_by?(prefix : String) : Bool
    starts_with?(prefix) && size > prefix.size
  end

  # :ditto:
  def prefixed_by?(prefix : Char) : Bool
    starts_with?(prefix) && size > 1
  end
end

module Novika
  # Words open entries they're assigned to in the dictionary
  # of their enclosing block.
  struct Word
    include Form

    # Death hook name.
    DIED = Word.new("*died")

    # Undefined word hook name.
    TRAP = Word.new("*trap")

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

    def opened(engine : Engine) : self
      if entry = engine.block.at?(self)
        # An entry exists for this word in the current block
        # or in its parents.
        entry.open(engine)
        return self
      end

      block = current = engine.block

      while block && (trap = block.at?(TRAP))
        # A trap entry exists for this word in *block*. Traps are
        # inherited as opposed to conversion words like *asDecimal.
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
        trap.open(engine)

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

    def val(engine : Engine? = nil, stack : Block? = nil)
      peel.onto(stack || Block.new)
    end

    # Converts this quoted word to `Word`.
    def to_word : Word
      Word.new(id.lstrip('#'))
    end

    def opened(engine) : self
      tap { peel.onto(engine.stack) }
    end

    def to_s(io)
      io << '#' << id
    end

    def_equals_and_hash id
  end
end
