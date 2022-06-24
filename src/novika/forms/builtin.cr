module Novika
  # Wraps a snippet of Crystal (native) code, namely a Crystal
  # `Proc`, for usage in the Novika-world.
  struct Builtin
    extend HasDesc

    include Form

    getter desc : String

    # :nodoc:
    getter code : World ->

    def initialize(@desc, @code)
    end

    def open(world)
      code.call(world)
    end

    def to_s(io)
      io << "[native code]"
    end

    def self.desc(io)
      io << "a builtin"
    end

    def_equals_and_hash code
  end
end
