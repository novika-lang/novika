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
      onto(engine.stack)
    end

    # Adds this form to *block*.
    def onto(block : Block) : self
      tap { block.add(self) }
    end

    # Returns the result of opening this form with *engine*.
    # Resembles Novika's own `F val`.
    #
    # Note: `val` is different from `open` in that it opens
    # this form with *engine* and retruns the result of opening
    # *immediately*, while `open` and friends only *schedule*
    # it for execution, making the result un-obtainable for
    # the Crystal code.
    #
    # In general, the purpose of `val` is to have a convenient
    # interface to call blocks from Crystal, which may be
    # especially useful for uses where very high performance
    # is desired.
    def val(engine : Engine? = nil, stack : Block? = nil)
      self
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
