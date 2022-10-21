module Novika
  # Novika dictionary protocol. Objects or values that want
  # to be Block dictionaries can implement this protocol to
  # make that possible.
  module IDict
    # Assigns *name* form to *entry* in this dictionary.
    abstract def set(name : Form, entry : Entry) : Entry

    # Returns the entry corresponding to *name* form in this
    # dictionary, or yields with *name* and returns the block
    # result.
    abstract def get(name : Form, & : Form -> Entry?) : Entry?

    # Returns whether this dictionary has an entry corresponding
    # to *name* form.
    abstract def has?(name : Form) : Bool

    # Imports entries from *donor* dictionary into this dictionary.
    #
    # Entries whose names are preceded by one or more `_` are
    # not imported (they are considered private).
    abstract def import!(donor : IDict)

    # Returns whether this dictionary currently stores no entries.
    abstract def empty? : Bool

    # Lists all name forms stored in this dictionary.
    abstract def names : Array(Form)

    # Returns a *shallow* copy of this dictionary.
    abstract def copy : IDict

    # Yields key, value forms in this dictionary.
    abstract def each(& : Form, Form ->)
  end

  # Default dictionary protocol implementation: default block
  # dictionary implementation. Uses a hash map for storage.
  #
  # Note: setting or getting with blocks as keys performs a
  # linear scan for now. The semantics for this is unstable.
  struct Dict
    include IDict

    # :nodoc:
    def initialize
      @store = {} of Form => Entry
    end

    protected def initialize(@store)
    end

    def set(name : Form, entry : Entry) : Entry
      if name.is_a?(Block)
        @store.each do |k, v|
          next unless k == name
          @store[k] = entry
          return entry
        end
      end

      @store[name] = entry
    end

    def get(name : Form) : Entry?
      if name.is_a?(Block)
        @store.each do |k, v|
          next unless k == name
          return v
        end
        return yield name
      end

      @store.fetch(name) { yield name }
    end

    def has?(name : Form) : Bool
      @store.has_key?(name)
    end

    def import!(donor : IDict)
      donor.each do |k, v|
        set(k, v) unless k.is_a?(Word) && k.id.prefixed_by?("_")
      end
    end

    def empty? : Bool
      @store.empty?
    end

    def names : Array(Form)
      @store.keys
    end

    def copy : IDict
      Dict.new(@store.dup)
    end

    def each
      @store.each { |k, v| yield k, v }
    end
  end

  # Represents a dictionary entry. Dictionary entries hold the
  # value form.
  class Entry
    # Returns the form currently held by this entry.
    getter form : Form

    def initialize(@form)
    end

    # See `Form#effect`, `Form#effect(io)`.
    delegate :effect, to: form

    # See the same method in `Form`.
    def onto(block : Block)
      form.onto(block)
    end

    # :ditto:
    def on_open(engine : Engine) : Nil
      onto(engine.stack)

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
    delegate :on_open, to: form
  end
end
