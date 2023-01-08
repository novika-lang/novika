module Novika
  # Holds and accepts information about an error.
  #
  # Errors are raised when a certain case is undesired, unhandleable,
  # or otherwise inappropriate to some form of computation.
  #
  # Errors can be *handled* and *unhandled*. *Unhandled* errors
  # generate an error `report` (generally to STDERR, but this
  # depends on the frontend). They are fatal for the program
  # they occur in.
  #
  # *Death handlers*, or *death traps*, when set up in code blocks
  # and/or their relatives, allow errors to be *handled*. For this
  # reason, errors are Novika `Form`s, and can be manipulated,
  # reported, and inspected from Novika.
  class Error < Exception
    include Form

    # How many trace entries to display at max.
    MAX_TRACE = 64

    # Returns a string describing the reasons of this error.
    getter details : String

    # Returns the form that (speculatively) caused this error.
    getter! form : Form

    # Holds a reference to the continuations block at the time
    # of death.
    property conts : Block?

    def initialize(@details, @form = nil)
    end

    def desc(io : IO)
      io << "error: '" << details << "'"
    end

    def self.typedesc
      "error"
    end

    # Reports about this error to *io*.
    #
    # Note: Colorize is used for colors and emphasis. If you
    # do not want Colorize in *io*, you can temporarily disable
    # it by setting `Colorize.enabled = false`.
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

      if form?
        io.puts "  ╿ this form is invalid, and is the cause of death:"
        io << "  │  " << form
        io.puts
      end

      io << "Sorry: ".colorize.red.bold << details

      case details.byte_at?(details.bytesize - 1)
      when '!', '?', '.'
      else
        io << '.'
      end
      io.puts
    end

    def to_s(io)
      io << "[" << details << "]"
    end
  end
end
