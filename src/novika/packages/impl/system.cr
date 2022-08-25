module Novika::Packages::Impl
  class System < ISystem
    def echo(engine, form : Form)
      puts form.enquote(engine).string
    end

    def readline(engine, prompt : Form) : {Quote, Boolean}
      string = prompt.enquote(engine).string
      answer = nil
      {% if flag?(:novika_readline) %}
        answer = Readline.readline(string)
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
