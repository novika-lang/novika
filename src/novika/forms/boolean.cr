module Novika
  # Represents a boolean (true/false) value.
  abstract struct Boolean
    include Form

    # Creates a `Boolean` subclass for the given *object*.
    def self.[](object) : Boolean
      object ? True.new : False.new
    end

    # Returns a `Boolean` for whether *a* and *b* are the same.
    #
    # Note that Novika's `same?` is not exactly the same as Crystal's,
    # that is, not as "pedantic".
    #
    # For example, some reference types may pretend they're value
    # types (see `ValueForm`). This means that e.g. `1 1 same?` in
    # Novika will leave `true`, but for Crystal it's actually false
    # because the two `1`s are different objects.
    def self.same?(a : ValueForm, b : ValueForm) : Boolean
      Boolean[a == b]
    end

    # :ditto:
    def self.same?(a : Reference, b : Reference) : Boolean
      Boolean[a.same?(b)]
    end

    # :ditto:
    def self.same?(a : Byteslice, b : Byteslice) : Boolean
      Boolean[a.same?(b)]
    end

    # :ditto:
    def self.same?(a, b) : Boolean
      Boolean[a == b]
    end

    def self.typedesc
      "boolean"
    end
  end

  # Represents a truthy `Boolean`.
  struct True < Boolean
    def desc(io : IO)
      io << "boolean true"
    end

    def self.typedesc
      "boolean"
    end

    def to_s(io)
      io << "true"
    end

    def_equals_and_hash
  end

  # Represents a falsey `Boolean`. `False` is the only falsey
  # form in Novika.
  struct False < Boolean
    def desc(io : IO)
      io << "boolean false"
    end

    def self.typedesc
      "boolean"
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
