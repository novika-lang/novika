module Novika
  # Represents Novika tables, which are form to form (or form
  # to entry) mappings.
  alias Table = Hash(Form, Entry)

  # Enables support for `entry:fetch`, `entry:exists?`,
  # `entry:isOpenEntry?`, and the derived words.
  module ReadableTable
    extend HasDesc

    # Raises with *details*.
    abstract def die(details : String)

    # Returns the table entry corresponding to *name*, or nil.
    def at?(name : Form) : Entry?
    end

    # Returns the table entry corresponding to *name*, or dies.
    def at(name : Form) : Entry
      at?(name) || die("undefined table property: #{name}")
    end

    # Returns whether this table has an entry corresponding
    # to *name*.
    def has?(name : Form)
      !!at?(name)
    end

    def self.desc(io : IO)
      io << "a readable table"
    end
  end

  # Represents a table entry. Table entries hold the value form.
  class Entry
    # Returns the form currently held by this entry.
    getter form : Form

    def initialize(@form)
    end

    # Pushes this entry's value form onto the active stack.
    delegate :push, to: form

    # :ditto:
    def open(engine : Engine) : self
      tap { push(engine) }
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
    def open(engine : Engine) : self
      tap { form.open(engine) }
    end
  end
end
