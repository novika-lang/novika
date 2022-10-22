module Novika::Features
  # TODO: maybe readLine should have something like Fancyline
  # has, i.e. return some sort of status {Accepted | Rejected
  # (CTRL-C) | EOF (CTRL-D), Quote?}.
  #
  # Then IOs#readline() should return record Response(status, response)

  abstract class ISystem
    include Feature

    def self.id : String
      "system"
    end

    def self.purpose : String
      "exposes all sorts of OS-related vocabulary, such as 'echo' and 'nap'"
    end

    def self.on_by_default? : Bool
      true
    end

    # Enquotes and appends *form* to the standard output stream.
    abstract def append_echo(engine, form : Form)

    # Enquotes and prints *prompt* to STDOUT. Waits for the
    # user to answer, enquotes the answer and returns it
    # together with a status boolean.
    #
    # If the user answered with EOF (e.g. CTRL-D), status bool
    # is false and answer quote is empty. Else, answer quote
    # contains the answer and status bool is true.
    abstract def readline(engine, prompt : Form) : {Quote, Boolean}

    # Reports abound an *error* to the standard error stream.
    abstract def report_error(engine, error : Error)

    # Sleeps for the given amount of *millis*econds.
    abstract def nap(engine, millis : Decimal)

    # Returns a reading from the monotonic clock, in milliseconds.
    abstract def monotonic(engine) : Decimal

    def inject(into target : Block)
      target.at("appendEcho", <<-END
      ( F -- ): enquotes and appends Form to the standard
       output stream.
      END
      ) { |engine, stack| append_echo(engine, stack.drop) }

      target.at("readLine", <<-END
      ( Pf -- Aq Sb ): enquotes and prints Prompt form to the
       standard output stream. Waits for the user to answer,
       enquotes the answer and leaves it.

      If user answered with EOF, Answer quote is empty and
      Status boolean is false. Else, Status boolean is true.

      >>> 'What is your name? ' readLine [ echo ] [ drop ] br
      What is your name? John Doe ⏎
      John Doe
      END
      ) do |engine, stack|
        answer, status = readline(engine, stack.drop)
        answer.onto(stack)
        status.onto(stack)
      end

      target.at("reportError", <<-END
      ( Eo -- ): reports about an error to the standard error
       stream, given an Error object.

      You can obtain an error object by, e.g., catching it
      in `*died`.
      END
      ) do |engine, stack|
        error = stack.drop.a(Error)

        report_error(engine, error)
      end

      # Monotonic doc is mostly "borrowed" from Crystal's.

      target.at("monotonic", <<-END
      ( -- Mt ): leaves a reading from the monotonic clock to
       measure elapsed time, in milliseconds.

      Values from the monotonic clock and wall clock are not
      comparable. Monotonic clock should be independent from
      discontinuous jumps in the system time, such as leap
      seconds, time zone adjustments or manual changes to the
      computer's clock.

      >>> monotonic $: start
      >>> 20 nap
      >>> monotonic $: end
      >>> end start -
      === 20 (approximately)
      END
      ) { |engine, stack| monotonic(engine).onto(stack) }

      target.at("nap", <<-END
      ( Nms -- ): sleeps for N decimal milliseconds.
      END
      ) do |engine, stack|
        millis = stack.drop.a(Decimal)

        nap(engine, millis)
      end
    end
  end
end
