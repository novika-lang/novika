module Novika::Frontend
  extend self

  # Appends a "wait" *message* to *io*.
  def wait(message, io = STDOUT)
    io << "\e[2K\r" << "Wait".colorize.bold << "  " << message
  end

  # Appends a "sorry" *message* to *io*
  def err(message, io = STDERR)
    io << "\e[2K\r" << "Sorry".colorize.red.bold << "  " << message
  end

  # Appends an "ok" *message* to *io*.
  def ok(message, io = STDOUT)
    io << "\e[2K\r" << "Ok".colorize.green.bold << "  " << message
  end

  # Appends a "note" *message* to *io*.
  def note(message, io = STDOUT)
    io << "\e[2K\r" << " Note".colorize.blue.bold << "  " << message
  end

  {% for name in %w(wait err ok note) %}
    # Calls `{{name.id}}`, and appends a newline, both using
    # with *io*.
    def {{name.id}}ln(message, io = STD{% if name == "err" %}ERR{% else %}OUT{% end %})
      {{name.id}}(message, io)
      io.puts
    end
  {% end %}

  # Issues a `wait` message *msg*, yields, then follows with
  # an OK message *okmsg*.
  def wait(msg, *, ok okmsg, &)
    wait(msg)
    yield
    okln(okmsg)
  end
end
