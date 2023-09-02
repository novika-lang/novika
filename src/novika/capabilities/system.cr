module Novika::Capabilities
  abstract class ISystem
    include Capability

    # A thin wrapper around the prompt configuration block of `readLine*`.
    struct PromptConfig
      MORE       = Word.new("more?")
      PROMPT     = Word.new("prompt")
      HISTORY    = Word.new("history")
      SUGGEST    = Word.new("suggest")
      DELIMITERS = Word.new("delimiters")

      def initialize(@carrier : Block)
      end

      # Returns the history entry in the carrier block, if any.
      def history_entry? : Entry?
        @carrier.entry_for?(HISTORY)
      end

      # Returns word delimiter quote, if any. The decision of how
      # to interpret the returned quote is up to the caller.
      def delimiters? : Quote?
        return unless entry = @carrier.entry_for?(DELIMITERS)

        Engine.exhaust(Engine.current.capabilities, entry).top.a(Quote)
      end

      # Returns `false` or nil if no more input is expected after
      # *expression*, otherwise, returns some form that the user
      # assigned "more" to or that they left on top of the stack
      # (interpreted as `true`).
      def more?(expression : String) : Form?
        return unless entry = @carrier.entry_for?(MORE)

        stack = Block.with(Quote.new(expression))

        Engine.exhaust(Engine.current.capabilities, entry, stack).top
      end

      # Returns the prompt quote for the given *line_number*, or nil
      # if no prompt should be used.
      def prompt?(line_number : Int32) : Quote?
        return unless entry = @carrier.entry_for?(PROMPT)

        stack = Block.with(Decimal.new(line_number))

        form = Engine.exhaust(Engine.current.capabilities, entry, stack).top
        form.to_quote
      end

      # Returns the title quote followed by suggestions block for
      # the given *word* and input *prior* to *word*.
      def suggest?(word : String, prior : String) : {Quote, Block}?
        return unless entry = @carrier.entry_for?(SUGGEST)

        if entry.is_a?(OpenEntry)
          # If entry is an opener entry, we should get the title and
          # the results from the stack.
          stack = Block.with(Quote.new(prior), Quote.new(word))
          block = Engine.exhaust(Engine.current.capabilities, entry, stack)
        else
          # If it's not an opener entry, we should be able to accept
          # a block like this one: [ 'foobar' [ 'x' 'y' 'z' ] ].
          block = entry.form.a(Block)
          unless block.count == 2
            block.die("expected block of the form [ title:quote [ ...suggestion:quote ] ]")
          end
        end

        title, suggestions = block.at(block.count - 2), block.at(block.count - 1)

        {title.a(Quote), suggestions.a(Block)}
      end
    end

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
    # user to answer, enquotes the answer (if any) and returns
    # it together with a status boolean.
    #
    # If the user answered with EOF (e.g. CTRL-D), status bool
    # is false and answer quote is nil. Else, answer quote
    # contains the answer and status bool is true.
    abstract def readline(engine, prompt : Form) : {Quote?, Boolean}

    # Extended (contextful) version of `readline`.
    abstract def readline_star(engine, config : PromptConfig) : {Quote?, Boolean}

    # Reports abound an *error* to the standard error stream.
    abstract def report_error(engine, error : Error)

    # Sleeps for the given amount of *millis*econds.
    abstract def nap(engine, millis : Decimal)

    # Returns a reading from the monotonic clock, in milliseconds.
    abstract def monotonic(engine) : Decimal

    # Ends the program with the given exit *code*.
    abstract def bye(engine, code : Decimal)

    def inject(into target : Block)
      target.at("appendEcho", <<-END
      ( F -- ): enquotes and appends Form to the standard
       output stream.
      END
      ) { |engine, stack| append_echo(engine, stack.drop) }

      target.at("readLine", <<-END
      ( Pf -- Aq true / false ): enquotes and prints Prompt
       form to the standard output stream. Waits for the user
       to answer, enquotes the answer and leaves it.

      If user answered the prompt, leaves Answer quote followed
      by boolean true. Otherwise, leaves boolean false.

      ```
      'What is your name? ' readLine => echo

      "INPUT: What is your name? John Doe⏎"
      "STDOUT: John Doe⏎"

      "INPUT: What is your name? <Ctrl-D>"
      "[Program exits]"
      ```
      END
      ) do |engine, stack|
        answer, status = readline(engine, stack.drop)
        answer.onto(stack) if answer
        status.onto(stack)
      end

      target.at("readLine*", <<-END
      ( Cb -- Aq true / false ): extended (contextful) version of `readLine`.
       Accepts Configuration block and leaves Answer quote followed by
       `true`, otherwise, if the prompt was rejected, leaves just `false`.

      ## Configuring the prompt

      To configure the prompt you should create a Configuration block
      and populate it with settings according to how you want the prompt
      to look like and work.

      ### Empty or meaningless configuration block

      If you pass an empty Configuration block or one that has no entries
      that are of interest to `readLine*`, then you will get an empty
      prompt but a prompt nonetheless (i.e. everything will work fine;
      *all of the settings below are opt-in*).

      ### Available settings

      #### `prompt`

      `prompt` allows you to assign the prompt quote. In case it is an
      opener entry it will be opened like so: `( L -- Pq )` where P is
      the prompt quote and L is the line number (because multiline editing
      is supported). So you can set custom prompts for every line, or
      use only one for all of them.

      ```
      [ '>>> ' $: prompt ] obj readLine*

      """
      >>> example inp|ut

      >>> example multiline
      >>> inp|ut
      """

      [ [ 1 = sel: '>>> ' '... ' ] @: prompt ] readLine*

      """
      >>> example multiline
      ... inp|ut
      """
      ```

      #### `history`

      If Configuration block has a `history` entry (a quote), then
      history is going to be saved to, and loaded from that entry.

      If there is no `history` entry in the Configuration block, then
      history is not going to be persisted.

      ```
      [ ('>>> ' $: prompt) ('' $: history) ] obj $: config

      loop: [
        config readLine* or: break

        [
          'h' [ config.history echo ]
          [ ] [ echo ]
        ] choose
      ]

      "Do something with the history after the loop breaks..."

      'History after the loop: ' config.history 2echo
      ```

      #### `more?`

      `more?` allows to specify whether more of the input should be
      expected, that is, if the prompt should continue on another line.

      By default it is `false`, and is expected to be boolean `false`
      or anything else (interpreted as `true`). If `more?` is an opener,
      it is expected to be compatible with the following signature:
      `( Paq -- true / false )`, where Paq is the partial answer quote.
      If the block leaves anything other than `true` or `false`, that
      is interpreted as `true`.

      ```
      [ [ 1 = sel: '>>> ' '... ' ] @: prompt

        [ orphan swap

          false $: result "< Don't need anything else..."

          [ "Oops, probably 'slurp' died, so let's try to wait
             for enough input to not make slurp die..."
            true =: result
          ] @: __died__

          slurp "Regardless of whether `slurp` dies, we end up here" result
        ] @: more?
      ] obj $: config

      'Enter parseable Novika code or I will go multiline:' echo

      loop: [ config readLine* br: echo break ]
      ```

      #### `delimiters`

      `delimiters` is a quote (or a block that leaves a quote in case
      `delimiters` is an opener entry) that lists *word delimiter*
      characters, useful for jumping through words and autocompletion.

      ```
      [ ('Enter your name> ' $: prompt) (' .,-' $: delimiters) ] obj $: config

      config readLine* or: okbye $: name

      [ 'Your name is: ' name ] ~* echo
      ```

      #### `suggest`

      If `suggest` is a pusher entry, it should be a block of the
      following shape: `[ title [ ...suggestion ] ]`, where `title`
      and every one of `suggestion`s are quotes.

      `title` followed by colon ':' is displayed above the list of
      suggestions. The list can be opened using the Tab key, escaped
      from using Escape.

      ```
      [ 'Enter your name> ' $: prompt

        [ 'Possible names'
          [ 'John'
            'Alice'
            'Mary'
            'David' ]
        ] $: suggest
      ] obj $: config

      config readLine*
      ```

      In case `suggest` is an opener, it is expected to be compatible
      with the following signature: `( P W -- Tq Sb )` where W is
      the current word (as per `delimiters`), P is the prior quote
      (all that precedes W), Tq is the title quote, and Sb is
      the suggestions block.

      ```
      [ 'Enter expression> ' $: prompt

        ' ' $: delimiters

        [ $: word $: prior

          'Possible evaluations (+, -, *)'

          [ [ ] prior slurp [+] 0 reduce
            [ ] prior slurp [-] 0 reduce
            [ ] prior slurp [*] 1 reduce
          ] vals
        ] @: suggest
      ] obj $: config

      config readLine*
      ```
      END
      ) do |engine, stack|
        carrier = stack.drop.a(Block)
        config = PromptConfig.new(carrier)
        answer, status = readline_star(engine, config)
        answer.onto(stack) if answer
        status.onto(stack)
      end

      target.at("reportError", <<-END
      ( Eo -- ): reports about an error to the standard error
       stream, given an Error object.

      You can obtain an error object by, e.g., catching it
      in `__died__`.
      END
      ) do |engine, stack|
        error = stack.drop.a(Error)

        report_error(engine, error)
      end

      # Monotonic doc is mostly "borrowed" from Crystal's.

      target.at("monotonic", <<-END
      ( -- R ): leaves a Reading from the monotonic clock to
       measure elapsed time, in milliseconds.

      Values from the monotonic clock and wall clock are not
      comparable. Monotonic clock should be independent from
      discontinuous jumps in the system time, such as leap
      seconds, time zone adjustments or manual changes to the
      computer's clock.

      ```
      monotonic $: start
      20 nap
      monotonic $: end
      end start - echo
      "STDOUT: 20⏎ (approximately)"
      ```
      END
      ) { |engine, stack| monotonic(engine).onto(stack) }

      target.at("nap", <<-END
      ( D -- ): sleeps a Duration of time, given in *milliseconds*.
      END
      ) do |engine, stack|
        millis = stack.drop.a(Decimal)

        nap(engine, millis)
      end

      target.at("bye", <<-END
      ( Ec -- ): ends the program with the given decimal Exit code.
      END
      ) do |engine, stack|
        code = stack.drop.a(Decimal)

        bye(engine, code)
      end
    end
  end
end
