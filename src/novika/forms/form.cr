module Novika
  # Form is an umbrella for words and blocks. Since some words
  # (like numbers, quotes) are just too different from words as
  # we know them, they have their own types directly subordinate
  # to Form.
  #
  # Make sure to override `self.typedesc` to avoid weird unrelated
  # Crystal errors. Crystal breaks at class-level inheritance.
  module Form
    # Raises `Died` providing *details*.
    def die(details : String)
      raise Died.new(details)
    end

    # :nodoc:
    #
    # Dies of assertion failure with *other* type.
    def afail(other : T.class) forall T
      die("bad type: #{self.class.typedesc}, expected: a #{T.typedesc}")
    end

    # Appends a string description of this form to *io*.
    def desc(io : IO)
      io << "a form"
    end

    # Returns a string description of this form.
    def desc : String
      String.build { |io| desc(io) }
    end

    # Selects either *a* or *b*. Novika defines `False` to be the
    # only form selecting *b*. All other forms select *a*.
    def sel(a, b)
      a
    end

    # Reacts to this form being opened in *engine*.
    def open(engine : Engine) : self
      opened(engine)
    end

    # Reacts to this form's enclosing block being opened in *engine*.
    def opened(engine : Engine) : self
      push(engine)
    end

    # Adds this form to *block*.
    def push(block : Block) : self
      tap { block.add(self) }
    end

    # Pushes this form onto *engine*'s active stack.
    def push(engine : Engine) : self
      push(engine.stack)
    end

    # Asserts that this form is of the given *type*. Dies if
    # it's not.
    def assert(engine : Engine, type : T.class) : T forall T
      is_a?(T) ? self : afail(T)
    end

    # Returns this form's quote representation. May run Novika,
    # hence the need for *engine*.
    def to_quote(engine : Engine) : Quote
      Quote.new(to_s)
    end
  end
end
