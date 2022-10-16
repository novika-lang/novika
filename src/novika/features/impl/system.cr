{% if flag?(:novika_readline) %}
  @[Link(ldflags: "#{__DIR__}/ext/liblinenoise.a")]
  lib Linenoise
    fun linenoise(prompt : UInt8*) : UInt8*
    fun linenoise_free = linenoiseFree(prompt : UInt8*) : UInt8*
  end
{% end %}

module Novika::Features::Impl
  class System < ISystem
    def append_echo(engine, form : Form)
      print form.to_quote.string
    end

    def readline(engine, prompt : Form) : {Quote, Boolean}
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
      {Quote.new(answer || ""), Boolean[!!answer]}
    end

    def report_error(engine, error : Died)
      error.report(STDERR)
    end

    def monotonic(engine) : Decimal
      Decimal.new(Time.monotonic.total_milliseconds)
    end

    def nap(engine, millis : Decimal)
      sleep millis.to_i.milliseconds
    end
  end
end
