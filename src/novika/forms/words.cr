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
  # Words open entries they're assigned to in the table of their
  # enclosing block.
  struct Word
    include Form
    extend HasDesc

    # Death hook name.
    DIED = Word.new("*died")

    # Undefined word hook name.
    TRAP = Word.new("*trap")

    # Returns the underlying string id.
    getter id : String

    def initialize(@id)
    end

    def desc(io : IO)
      io << "a word named " << id
    end

    def self.desc(io : IO)
      io << "a word"
    end

    def opened(engine : Engine) : self
      if entry = engine.block.at?(self)
        # An entry exists for this word in the CC block.
        entry.open(engine)
      elsif trap = engine.block.at?(TRAP)
        # An undefined word trap exists in the CC block. Quote
        # this word open it.
        engine.stack.add QuotedWord.new(id)
        trap.open(engine)
      else
        # No entry and no trap: err out.
        die("definition for #{self} not found in the enclosing block(s)")
      end
      self
    end

    def to_s(io)
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
    extend HasDesc

    # Returns the underlying string id.
    getter id : String

    def initialize(@id)
    end

    def desc(io : IO)
      io << "a quoted word named " << id
    end

    def self.desc(io : IO)
      io << "a quoted word"
    end

    # "Peels" off a layer of quoting.
    #
    # ```
    # QuotedWord.new("#foo").unquote   # Word.new("foo")
    # QuotedWord.new("##foo").unquote  # QuotedWord.new("#foo")
    # QuotedWord.new("###foo").unquote # QuotedWord.new("##foo")
    # ```
    def peel
      id.prefixed_by?('#') ? QuotedWord.new(id.lchop) : Word.new(id)
    end

    def opened(engine) : self
      tap { peel.push(engine) }
    end

    def to_s(io)
      io << '#' << id
    end

    def_equals_and_hash id
  end
end
