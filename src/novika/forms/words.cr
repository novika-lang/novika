class String
  # Returns whether this string starts with *prefix* but also
  # has other characters after it.
  def prefixed_by?(prefix : String)
    starts_with?(prefix) && size > prefix.size
  end

  # :ditto:
  def prefixed_by?(prefix : Char)
    starts_with?(prefix) && size > 1
  end
end

module Novika
  # Words open entries they're assigned to in the table of their
  # enclosing block.
  struct Word
    extend HasDesc

    include Form

    # Standard death handler entry name.
    DIED = Word.new("*died")

    # Standard word trap entry name.
    TRAP = Word.new("*trap")

    # Returns the underlying string id.
    getter id : String

    def initialize(@id)
    end

    def desc
      "a word named #{id}"
    end

    def opened(world)
      if entry = world.block.at?(self)
        entry.open(world)
      elsif trap = world.block.at?(TRAP)
        world.stack.add QuotedWord.new(id)
        trap.open(world)
      else
        die("definition for #{self} not found in the enclosing block(s)")
      end
    end

    def to_s(io)
      io << id
    end

    def self.desc(io)
      io << "a word"
    end

    def_equals_and_hash id
  end

  # Quoted words are words prefixed by '#': e.g., `#foo`. It lets
  # you keep automatic word opening one manual `open` away.
  struct QuotedWord
    extend HasDesc
    include Form

    # Returns the underlying string id.
    getter id : String

    def initialize(@id)
    end

    def desc
      "a quoted word named #{id}"
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

    def opened(world)
      peel.push(world)
    end

    def to_s(io)
      io << '#' << id
    end

    def self.desc(io)
      io << "a quoted word"
    end

    def_equals_and_hash id
  end
end
