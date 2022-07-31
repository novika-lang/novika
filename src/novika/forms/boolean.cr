module Novika
  # Represents a boolean (true/false) value.
  abstract struct Boolean
    include Form
    extend HasDesc

    # Creates a `Boolean` subclass for the given *object*.
    def self.[](object) : Boolean
      object ? True.new : False.new
    end

    # Returns a `Boolean` for whether *a* and *b* are the same.
    def self.same?(a : Reference, b : Reference) : Boolean
      Boolean[a.same?(b)]
    end

    # :ditto:
    def self.same?(a, b) : Boolean
      Boolean[a == b]
    end

    def self.desc(io : IO)
      io << "a boolean"
    end
  end

  # Represents a truthy `Boolean`.
  struct True < Boolean
    extend HasDesc

    def desc(io : IO)
      io << "boolean true"
    end

    def self.desc(io : IO)
      io << "boolean true"
    end

    def to_s(io)
      io << "true"
    end

    def_equals_and_hash
  end

  # Represents a falsey `Boolean`. `False` is the only falsey
  # form in Novika.
  struct False < Boolean
    extend HasDesc

    def desc(io : IO)
      io << "boolean false"
    end

    def self.desc(io : IO)
      io << "boolean false"
    end

    def sel(a, b)
      b
    end

    def to_s(io)
      io << "false"
    end

    def_equals_and_hash
  end
end
