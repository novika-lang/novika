@[Link(ldflags: "#{__DIR__}/ext/liblinenoise.a")]
lib Linenoise
  fun linenoise(prompt : UInt8*) : UInt8*
  fun linenoise_free = linenoiseFree(prompt : UInt8*) : UInt8*
end

module Novika::Packages::Impl
  class System < ISystem
    def echo(engine, form : Form)
      puts form.to_quote(engine).string
    end

    def readline(engine, prompt : Form) : {Quote, Boolean}
      string = prompt.to_quote(engine).string
      buffer = Linenoise.linenoise(string.to_unsafe)
      unless buffer.null?
        answer = String.new(buffer)
        Linenoise.linenoise_free(buffer)
      end
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
