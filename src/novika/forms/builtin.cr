module Novika
  # Wraps a snippet of Crystal (native) code, namely a Crystal
  # `Proc`, for usage in the Novika-land.
  struct Builtin
    include Form

    # :nodoc:
    getter code : Engine, Block ->

    def initialize(@desc : String, @code)
    end

    def desc(io : IO)
      io << @desc
    end

    def self.typedesc
      "builtin"
    end

    def open(engine : Engine)
      code.call(engine, engine.stack)
    end

    def val(engine : Engine? = nil, stack : Block? = nil)
      stack ||= Block.new
      engine ||= Engine.new
      engine.schedule(self, stack)
      engine.exhaust
      stack.drop
    end

    def to_s(io)
      io << "[native code]"
    end

    def_equals_and_hash code
  end
end
