module Novika
  # Represents a boolean (true/false) value.
  abstract struct Boolean
    extend HasDesc

    include Form

    # Creates a `Boolean` subclass for the given *object*.
    def self.[](object)
      object ? True.new : False.new
    end

    # Returns a `Boolean` for whether two objects, *a* and
    # *b*, are the same.
    def self.same?(a : Reference, b : Reference)
      Boolean[a.same?(b)]
    end

    # :ditto:
    def self.same?(a, b)
      Boolean[a == b]
    end

    def self.desc(io)
      io << "a boolean"
    end
  end

  # Represents a truthy `Boolean`.
  struct True < Boolean
    extend HasDesc

    def desc
      "boolean true"
    end

    def to_s(io)
      io << "true"
    end

    def self.desc(io)
      io << "boolean true"
    end

    def_equals_and_hash
  end

  # Represents a falsey `Boolean`. `False` is the only falsey
  # form in Novika.
  struct False < Boolean
    extend HasDesc

    def desc
      "boolean false"
    end

    def sel(a, b)
      b
    end

    def to_s(io)
      io << "false"
    end

    def self.desc(io)
      io << "boolean false"
    end

    def_equals_and_hash
  end
end
