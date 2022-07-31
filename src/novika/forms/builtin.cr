module Novika
  # Wraps a snippet of Crystal (native) code, namely a Crystal
  # `Proc`, for usage in the Novika-land.
  struct Builtin
    include Form
    extend HasDesc

    # :nodoc:
    getter code : Engine ->

    def initialize(@desc : String, @code)
    end

    def desc(io : IO)
      io << @desc
    end

    def self.desc(io : IO)
      io << "a builtin"
    end

    def open(engine : Engine)
      code.call(engine)
    end

    def to_s(io)
      io << "[native code]"
    end

    def_equals_and_hash code
  end
end
