{% if flag?(:novika_readline) %}
  @[Link(ldflags: "#{__DIR__}/ext/liblinenoise.a")]
  lib Linenoise
    fun linenoise(prompt : UInt8*) : UInt8*
    fun linenoise_free = linenoiseFree(prompt : UInt8*) : UInt8*
  end
{% end %}

module Novika::Capabilities::Impl
  class System < ISystem
    def append_echo(engine, form : Form)
      print form.to_quote.string
    end

    def readline(engine, prompt : Form) : {Quote?, Boolean}
      string = prompt.to_quote.string
      answer = nil
      {% if flag?(:novika_readline) %}
        buffer = Linenoise.linenoise(string.to_unsafe)
        unless buffer.null?
          answer = String.new(buffer)
          Linenoise.linenoise_free(buffer)
        end
      {% else %}
        print string
        answer = gets
      {% end %}
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