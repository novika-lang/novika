module Novika
  # Represents a boolean (true/false) value.
  abstract struct Boolean
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
  end

  # Represents a truthy `Boolean`.
  struct True < Boolean
    def desc
      "boolean true"
    end

    def to_s(io)
      io << "true"
    end

    def_equals_and_hash
  end

  # Represents a falsey `Boolean`. `False` is the only falsey
  # form in Novika.
  struct False < Boolean
    def desc
      "boolean false"
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
