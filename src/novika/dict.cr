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

    # Deletes the entry corresponding to *name* form in this
    # dictionary if it exists. Otherwise, does nothing.
    abstract def del(name : Form)

    # Removes all entries in this dictionary.
    abstract def clear

    # Returns whether this dictionary has an entry corresponding
    # to *name* form.
    abstract def has?(name : Form) : Bool

    # Imports entries from *donor* dictionary into this dictionary.
    #
    # Entries whose names are preceded by one or more `_` are
    # not imported (they are considered private).
    abstract def import!(donor : IDict)

    # Returns the amount of entries in this dictionary.
    abstract def count : Int32

    # Returns a *shallow* copy of this dictionary.
    abstract def copy : IDict

    # Yields key, value forms in this dictionary.
    abstract def each(& : Form, Form ->)

    # Converts this dictionary to the standard `Dict` implementation
    # (used in e.g. serialization).
    abstract def to_dict : Dict

    # Returns whether this dictionary currently stores no entries.
    def empty? : Bool
      count.zero?
    end
  end

  # Default dictionary protocol implementation: default block
  # dictionary implementation. Uses a hash map for storage.
  #
  # Note: setting or getting with blocks as keys performs a
  # linear scan for now. The semantics for this is unstable.
  class Dict
    include IDict

    # Stores blocks. Looking up/setting blocks is an O(N) operation.
    # All of this is invisible to the Novika user and could (or so
    # I hope) be optimized...
    private getter blockstore : Array({Block, Entry}) { [] of {Block, Entry} }

    # :nodoc:
    def initialize
      @store = {} of Form => Entry
    end

    protected def initialize(@store, @blockstore = nil)
    end

    private def set_block(name : Block, entry : Entry) : Entry
      @blockstore.try do |bs|
        bs.each_with_index do |(k, _), index|
          next unless k == name
          bs[index] = {k, entry}
          return entry
        end
      end

      blockstore << {name, entry}

      entry
    end

    private def get_block(name : Block, &) : Entry?
      return unless bs = @blockstore
      bs.each do |k, v|
        next unless k == name
        return v
      end
      yield name
    end

    private def del_block(name : Block)
      return unless bs = @blockstore
      return unless index = bs.index { |k, _| k == name }

      bs.delete_at(index)
    end

    private def has_block?(name : Block) : Bool
      return false unless bs = @blockstore

      bs.any? { |k, _| k == name }
    end

    def set(name : Form, entry : Entry) : Entry
      return set_block(name, entry) if name.is_a?(Block)

      @store[name] = entry
    end

    def get(name : Form, &) : Entry?
      return get_block(name) { yield name } if name.is_a?(Block)

      @store.fetch(name) { yield name }
    end

    def del(name : Form)
      name.is_a?(Block) ? del_block(name) : @store.delete(name)
    end

    def clear
      @store.clear
      @blockstore.try &.clear
    end

    def has?(name : Form) : Bool
      name.is_a?(Block) ? has_block?(name) : @store.has_key?(name)
    end

    def import!(donor : IDict)
      donor.each do |k, v|
        set(k, v) unless k.is_a?(Word) && k.private?
      end
    end

    def count : Int32
      @store.size + (@blockstore.try &.size || 0)
    end

    def copy : IDict
      Dict.new(@store.dup, @blockstore.try &.dup)
    end

    def each(&)
      @store.each { |k, v| yield k, v }
      @blockstore.try &.each { |k, v| yield k, v }
    end

    def to_dict : Dict
      self
    end

    def ==(other : Dict)
      return false unless @store == other.@store
      return false unless @blockstore.class == other.@blockstore.class
      return true unless bs_l = @blockstore # return true if both are nil

      bs_r = other.@blockstore.not_nil!

      return false unless bs_l.size == bs_r.size

      # O(n^2) because programmable == override, __=__, is planned,
      # and it could in principle modify either (or both!) parties.
      bs_l.all? { |k_l, v_l| bs_r.any? { |k_r, v_r| k_l == k_r && v_l == v_r } }
    end
  end

  # Represents a dictionary entry. Dictionary entries hold the
  # value form.
  class Entry
    include Schedulable

    getter? opener
    getter form

    def initialize(@form : Form, @opener = false)
    end

    delegate :effect, :onto, to: @form

    def on_open(engine : Engine) : Nil
      @opener ? @form.on_open(engine) : onto(engine.stack)
    end

    def schedule(engine : Engine, stack : Block)
      @opener ? @form.schedule(engine, stack) : super
    end

    def schedule!(engine : Engine, stack : Block)
      @opener ? @form.schedule!(engine, stack) : super
    end

    def submit(@form)
      self
    end

    def_equals_and_hash @form, @opener
  end

  # Implementors act like a form-to-form mapping where entry
  # kind (opens/pushes) is ignored (basically, a read-only,
  # restricted subset of block methods for dictionary access).
  #
  # Implementors can be targets of `entry:fetch`, `entry:fetch?`,
  # `entry:exists?`, `entry:opener?`.
  module IReadableStore
    def self.typedesc
      "readable store"
    end

    # Returns whether this store has an entry with the given *name*.
    abstract def has_form_for?(name : Form) : Bool

    # Returns the value form for an entry with the given *name*, or
    # nil if no such entry exists.
    abstract def form_for?(name : Form) : Form?

    # Returns whether *name* opens its value form, as defined in this
    # store. Dies if *name* is not defined in this store.
    abstract def opener?(name : Form) : Bool

    # Returns whether *name* pushes its value form, as defined in this
    # store. Dies if *name* is not defined in this store.
    abstract def pusher?(name : Form) : Bool

    # Returns the value form for an entry with the given *name*, or
    # dies if no such entry exists.
    def form_for(name : Form) : Form
      form_for?(name) || name.die("no value form for '#{name}'")
    end
  end

  # Implementors can be targets of `entry:submit`.
  module ISubmittableStore
    def self.typedesc
      "submittable store"
    end

    # Submits value *form* to an entry with the given *name*.
    # Returns nil if no such entry exists.
    abstract def submit?(name : Form, form : Form)

    # Submits value *form* to an entry with the given *name*.
    # Dies if no such entry exists.
    def submit(name : Form, form : Form)
      submit?(name, form) || name.die("no entry to submit to")
    end
  end
end
