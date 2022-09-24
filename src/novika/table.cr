module Novika
  # Novika table protocol. Objects or values that want to be
  # `Block#table`s can implement this protocol to make that
  # possible.
  module ITable
    # Assigns *name* form to *entry* in this table.
    abstract def set(name : Form, entry : Entry) : Entry

    # Returns the entry corresponding to *name* form in this
    # table, or yields with *name* and returns the block result.
    abstract def get(name : Form, & : Form -> Entry?) : Entry?

    # Returns whether this table has an entry corresponding
    # to *name* form.
    abstract def has?(name : Form) : Bool

    # Imports entries from *donor* table into this table.
    #
    # Entries whose names are preceded by one or more `_` are
    # not imported (they are considered private).
    abstract def import!(donor : Table)

    # Returns whether this table currently stores no entries.
    abstract def empty? : Bool

    # Lists all name forms stored in this table.
    abstract def names : Array(Form)

    # Returns a *shallow* copy of this table.
    abstract def copy : ITable
  end

  # Default table protocol implementation: default block table
  # implementation. Uses a hash map for storage.
  struct Table
    include ITable

    @store = {} of Form => Entry

    # :nodoc:
    def initialize
    end

    protected def initialize(@store)
    end

    def set(name : Form, entry : Entry) : Entry
      @store[name] = entry
    end

    def get(name : Form) : Entry?
      @store.fetch(name) { yield name }
    end

    def has?(name : Form) : Bool
      @store.has_key?(name)
    end

    def import!(donor : Table)
      other = donor.@store

      other.each do |k, v|
        @store[k] = v unless k.is_a?(Word) && k.id.prefixed_by?("_")
      end
    end

    def empty? : Bool
      @store.empty?
    end

    def names : Array(Form)
      @store.keys
    end

    def copy : ITable
      Table.new(@store.dup)
    end
  end

  # Represents a table entry. Table entries hold the value form.
  class Entry
    # Returns the form currently held by this entry.
    getter form : Form

    def initialize(@form)
    end

    # See the same method in `Form`.
    delegate :push, to: form

    # Works just like `open`, but returns the result immediately.
    #
    # For details on the difference between `open` and `val`,
    # see `Form#val`.
    def val(engine : Engine? = nil, stack : Block = nil)
      form
    end

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
    # See the same method in `Form`.
    delegate :open, :val, to: form
  end
end
