struct Union(*T)
  # Joins union members' `Form#typedesc`.
  def self.typedesc
    String.build do |io|
      {% begin %}
        {% for member, index in T %}
          io << {{member}}.typedesc
          {% if index == T.size - 1 %}
          {% elsif index == T.size - 2 %}
            {% if T.size == 2 %}
              io << " or "
            {% else %}
              io << ", or "
            {% end %}
          {% else %}
            io << ", "
          {% end %}
        {% end %}
      {% end %}
    end
  end
end

module Novika
  # Form is an umbrella for words and blocks. Since some words
  # (like numbers, quotes) are just too different from words as
  # we know them, they have their own types directly subordinate
  # to Form.
  #
  # Make sure to override `self.typedesc` to avoid weird unrelated
  # Crystal errors. Crystal breaks at class-level inheritance.
  module Form
    # Raises an `Error` providing *details*.
    def die(details : String)
      raise Error.new(details, form: self)
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

    # Reacts to this form being opened with *engine*.
    def on_open(engine : Engine) : self
      on_parent_open(engine)
    end

    # Reacts to this form's enclosing block being opened with *engine*.
    def on_parent_open(engine : Engine) : self
      onto(engine.stack)
    end

    # Adds this form to *block*.
    def onto(block : Block) : self
      tap { block.add(self) }
    end

    # Asserts that this form is of the given *type*. Dies if
    # it's not.
    def a(type : T.class) : T forall T
      is_a?(T) ? self : afail(T)
    end

    # Returns this form's quote representation.
    def to_quote : Quote
      Quote.new(to_s)
    end

    # Generates and returns a description for the stack effect
    # of this form.
    #
    # For all forms except blocks and builtins, simply returns
    # their string representation.
    #
    # For blocks and builtins, tries to extract a `( ... -- ... )`
    # (but see `EFFECT_PATTERN`) from their corresponding
    # comment. If could not extract or no comment, returns
    # 'a block' for blocks and 'native code' for builtins.
    def effect(io)
      to_s(io)
    end

    # :ditto:
    def effect
      String.build { |io| effect(io) }
    end
  end
end
