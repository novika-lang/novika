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
    extend HasDesc

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

    def self.desc(io : IO)
      io << "an error"
    end

    # Generates an error report, and appends it to *io*.
    def report(io : IO)
      io << "Sorry: ".colorize.red.bold << details << "."
      io.puts
      io.puts

      # Conserved conts.
      return unless cconts = conts

      omitted = Math.max(0, cconts.count - MAX_TRACE)
      count = cconts.count - omitted

      cconts.each.skip(omitted).with_index do |cont_, index|
        if cont_.is_a?(Block)
          io << "  " << (index == count - 1 ? '└' : '├') << ' '
          io << "IN".colorize.bold << ' '
          cblock = cont_.at?(Engine::C_BLOCK_AT)
          cblock.is_a?(Block) ? cblock.spotlight(io) : io << (cblock || "[invalid continuation block]")
          io.puts

          io << "  " << (index == count - 1 ? ' ' : '│') << ' '
          io << "OVER".colorize.bold << ' ' << (cont_.at?(Engine::C_STACK_AT) || "[invalid continuation stack]")
          io.puts
        else
          io << "INVALID CONTINUATION".colorize.red.bold
        end
      end

      io.puts
    end

    def to_s(io)
      io << "[" << details << "]"
    end
  end
end
