module Novika
  # Wraps a snippet of Crystal (native) code, namely a Crystal
  # `Proc`, for usage in the Novika-land.
  struct Builtin
    include Form

    # Returns the identifier of this builtin.
    getter id : String

    # :nodoc:
    getter code : Engine, Block ->

    def initialize(@id : String, @desc : String, @code)
    end

    def desc(io : IO)
      io << @desc
    end

    def self.typedesc
      "builtin"
    end

    def on_parent_open(engine : Engine) : self
      code.call(engine, engine.stack)
      self
    end

    def effect(io)
      @desc =~ EFFECT_PATTERN ? (io << $1) : "native code"
    end

    def to_s(io)
      io << "[native code for: '" << id << "']"
    end

    def_equals_and_hash code
  end
end
