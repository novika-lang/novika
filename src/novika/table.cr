module Novika
  # Represents Novika tables, which are form to form (or form
  # to entry) mappings.
  alias Table = Hash(Form, Entry)

  # Enables support for `entry:fetch`, `entry:exists?`,
  # `entry:isOpenEntry?`, and the derived words.
  module ReadableTable
    extend HasDesc

    # Raises with *details*.
    abstract def die(details)

    # Returns the table entry for *name*, or nil.
    def at?(name : Form) : Entry?
    end

    # Returns the table entry for *name*, or dies.
    def at(name : Form) : Entry
      at?(name) || die("undefined table property: #{name}")
    end

    # Returns whether this table has *name* table entry.
    def has?(name)
      !!at?(name)
    end

    def self.desc(io)
      io << "a readable table"
    end
  end

  # Represents a table entry. Holds the value form.
  class Entry
    # Returns the form held by this entry.
    getter form : Form

    def initialize(@form)
    end

    # Pushes this entry's value form onto the active stack.
    delegate :push, to: form

    # :ditto:
    def open(world)
      push(world)
    end

    # Makes *form* the value form of this entry.
    def submit(@form)
      self
    end

    def_equals_and_hash form
  end

  # A kind of entry that, when opened, in turn opens its
  # value form.
  class OpenEntry < Entry
    # Opens this entry's value form in *world*.
    def open(world)
      form.open(world)
    end
  end
end
