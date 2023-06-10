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
  # Marks this object as schedulable in `Engine`.
  module Schedulable
    # The includer should be a `Form`.
    #
    # If the scheduled stack is the same as the active stack,
    # the includer form is simply opened (see `Form#on_open`)
    # without any kind of scheduling or waiting for the engine
    # to pick it up.
    #
    # However, if the scheduled stack is different from the
    # active stack, things get just a bit more difficult.
    #
    # Namely, a fictious block holding this form is created,
    # and scheduled "as normal". Then, this form is also
    # simply opened.
    #
    # Note that we *do not* set the fictious block's cursor
    # to 0. This handles the following two things.
    #
    # First, the engine won't try to open the includer form
    # again on the next interpreter loop cycle (remember we
    # already called `Form#on_open` on it).
    #
    # Second, if *form* schedules something else, all will work
    # as expected: first, this something will run, and then all
    # that's above, again, without re-running the includer form
    # because the cursor is past it.
    module ShouldOpenWhenScheduled
      def schedule!(engine : Engine, stack : Block)
        unless stack.same?(engine.stack)
          engine.schedule!(stack: stack, block: Block[self])
        end

        on_open(engine)
      end
    end

    # Unsafe `schedule`. Use `schedule` unless you have instantiated
    # this form yourself, or know what you're doing.
    #
    # Override this if you want to implement both safe `schedule`
    # and unsafe `schedule!` for your form type: safe `schedule`
    # simply delegates to `schedule!` unless it is explicitly
    # overridden.
    #
    # By default, simply pushes this form onto *stack*.
    def schedule!(engine : Engine, stack : Block)
      onto(stack)
    end

    # Safe `schedule`. Schedules this form for opening (aka
    # execution or evaluation) in *engine*, or opens it
    # immediately (see `ShouldOpenWhenScheduled`).
    #
    # See `Engine` to learn about the difference between `schedule`,
    # `on_open`, and `on_parent_open`.
    def schedule(engine : Engine, stack : Block)
      schedule!(engine, stack)
    end
  end

  # Includers are classes (that is, reference types) that want
  # to pretend they're value forms, i.e., value types.
  module ValueForm
  end

  # Form is an umbrella for words and blocks. Since some words
  # (like numbers, quotes) are just too different from words as
  # we know them, they have their own types directly subordinate
  # to Form.
  #
  # Make sure to override `self.typedesc` to avoid weird unrelated
  # Crystal errors. Crystal breaks at class-level inheritance.
  module Form
    include Schedulable

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
