module Novika
  # Represents Novika tables, which are form to form (or form
  # to entry) mappings.
  alias Table = Hash(Form, Entry)

  # Represents a table entry. Table entries hold the value form.
  class Entry
    # Returns the form currently held by this entry.
    getter form : Form

    def initialize(@form)
    end

    # Pushes this entry's value form onto the active stack.
    delegate :push, to: form

    # :ditto:
    def open(engine : Engine) : Nil
      push(engine)

      nil
    end

    # Makes *form* the value form of this entry.
    def submit(@form) : self
      self
    end

    def_equals_and_hash form
  end

  # A kind of entry that, when opened, in turn opens its
  # value form.
  class OpenEntry < Entry
    # Opens this entry's value form in *engine*.
    def open(engine : Engine) : Nil
      form.open(engine)

      nil
    end
  end
end
