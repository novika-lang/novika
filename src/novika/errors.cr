module Novika
  # Represents failure during execution in the `Engine`.
  #
  # There are two Novika-related exceptions: `Died`, which is
  # normally caused *explicitly* by the user (e.g., by adding
  # a number to a string)), and `EngineFailure`, which is raised
  # when `Engine` can't continue executing. Engine failures
  # are impossible to catch from inside Novika, because to
  # catch them would require an engine.
  class EngineFailure < Exception
    def initialize(@e : Died)
    end

    # See `Died#report`.
    def report(io : IO)
      @e.report(io)
    end
  end

  # Raised when a form dies.
  class Died < Exception
    include Form

    # How many trace entries to display at max.
    MAX_TRACE = 64

    # Returns a string describing the reasons of this death.
    getter details : String

    # Holds a reference to the continuations block at the time
    # of death.
    property conts : Block?

    def initialize(@details)
    end

    def desc(io : IO)
      io << "error: '" << details << "'"
    end

    def self.typedesc
      "error"
    end

    # Appends a report about this error to *io*.
    def report(io : IO)
      if conts = self.conts
        b = Math.max(0, conts.count - MAX_TRACE)
        e = conts.count

        unless b.zero?
          io << "  │ … " << b - 1 << " continuation(s) omitted …"
          io.puts
        end

        (b...e).each do |index|
          io << "  ╿ due to "

          cont = conts.at(index).as?(Block)
          code = cont.try &.at?(Engine::C_BLOCK_AT).as?(Block)
          unless cont && code
            io.puts "[malformed continuation]"
            next
          end

          io << "'" << code.top.colorize.bold << "', which was opened here:"
          io.puts
          io << "  │  "
          code.spot(io)
          io.puts
        end
      end
      io << "Sorry: ".colorize.red.bold << details << "."
      io.puts
    end

    def to_s(io)
      io << "[" << details << "]"
    end
  end
end
