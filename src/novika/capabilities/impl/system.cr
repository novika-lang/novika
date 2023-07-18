require "reply"

module Novika::Capabilities::Impl
  private class BlockHistory < Reply::History
    # A dummy IO to indicate that we should save history to
    # the block rather than to some file/IO.
    private class HistoryEntrySentinel < IO
      def read(slice : Bytes)
        0
      end

      def write(slice : Bytes) : Nil
      end
    end

    # :ditto:
    HistoryEntry = HistoryEntrySentinel.new

    @entry : Entry?

    def initialize(@config : ISystem::PromptConfig)
      @entry = @config.history_entry?

      super()
    end

    def clear
      super

      @entry.submit(Quote::EMPTY)
    end

    # Loads history from the config block's history entry.
    def load(io : HistoryEntrySentinel)
      return unless entry = @entry

      quote = entry.form.to_quote

      memory = IO::Memory.new
      quote.string.to_s(memory)

      memory.rewind

      load(memory)
    end

    # Saves history to the config block's history entry.
    def save(io : HistoryEntrySentinel)
      return unless entry = @entry

      history = String.build { |io| save(io) }

      entry.submit Quote.new(history)
    end
  end

  private class PromptReader < Reply::Reader
    def initialize(@config : ISystem::PromptConfig)
      @history = BlockHistory.new(@config)

      super()

      if delimiters = @config.delimiters?
        self.word_delimiters = delimiters.string.chars
      end
    end

    def history_file
      # Save to the history entry, not to a file/etc... If the user
      # doesn't want disk we shouldn't do disk.
      BlockHistory::HistoryEntry
    end

    def continue?(expression : String) : Bool
      form = @config.more?(expression)

      !(form.nil? || form.is_a?(False))
    end

    def prompt(io : IO, line_number : Int32, color? : Bool)
      return unless quote = @config.prompt?(line_number)

      io << quote.string
    end

    def auto_complete(current_word : String, expression_before : String)
      return super unless result = @config.suggest?(current_word, expression_before)

      title, suggestions = result

      results = [] of String
      suggestions.each do |suggestion|
        results << suggestion.to_quote.string
      end

      {title.string, results}
    end
  end

  class System < ISystem
    def append_echo(engine, form : Form)
      print form.to_quote.string
    end

    def readline_star(engine, config : PromptConfig) : {Quote?, Boolean}
      reader = PromptReader.new(config)
      answer = reader.read_next
      {answer ? Quote.new(answer) : nil, Boolean[!!answer]}
    end

    def readline(engine, prompt : Form) : {Quote?, Boolean}
      string = prompt.to_quote.string
      print string
      answer = gets
      {answer ? Quote.new(answer) : nil, Boolean[!!answer]}
    end

    def report_error(engine, error : Error)
      error.report(STDERR)
    end

    def monotonic(engine) : Decimal
      Decimal.new(Time.monotonic.total_milliseconds)
    end

    def nap(engine, millis : Decimal)
      sleep millis.to_i.milliseconds
    end

    def bye(engine, code : Decimal)
      exit code.to_i
    end
  end
end
