module Novika
  # A form that has class description.
  module HasDesc
    # Appends the description of this form class to *io*.
    abstract def desc(io)

    # Returns the description of this form class.
    def desc
      String.build { |io| desc(io) }
    end
  end

  # Form is an umbrella for words and blocks. Since some words
  # (like numbers, quotes) are just too different from words as
  # we know them, they have their own types directly subordinate
  # to Form.
  module Form
    extend HasDesc

    # Raised when a form dies.
    class Died < Exception
      # Returns a string describing the reasons of this death.
      getter details : String

      def initialize(@details)
      end
    end

    # Raises `Died` providing *details*.
    def die(details)
      raise Died.new(details)
    end

    # Returns a string description of this form.
    def desc
      "a form"
    end

    # Selects either *a* or *b*. Novika defines `False` to be the
    # only form selecting *b*. All other forms select *a*.
    def sel(a, b)
      a
    end

    # Reacts to this form being opened in *world*.
    def open(world)
      opened(world)
    end

    # Reacts to this form's enclosing block being opened in *world*.
    def opened(world)
      push(world)
    end

    # Adds this form to *block*.
    def push(block : Block)
      block.add(self)
    end

    # Pushes this form onto *world*'s active stack.
    def push(world : World)
      push(world.stack)
    end

    # Asserts that this form is of the given *type*. Dies if
    # it's not.
    def assert(type : T.class) forall T
      return self if is_a?(T)

      l, r = self.class, type
      ldesc = l.is_a?(HasDesc) ? l.desc : l.class
      rdesc = r.is_a?(HasDesc) ? r.desc : r.class
      die("bad type: #{ldesc}, expected: #{rdesc}")
    end

    # Returns this form's quote representation. May require
    # Novika code to be run. Hence *world* has to be provided,
    # and the name is so strange.
    def enquote(world)
      Quote.new(to_s)
    end

    def self.desc(io)
      io << "a form"
    end
  end
end
