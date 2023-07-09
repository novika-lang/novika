module Novika
  # Class-side (`extend`) interface to a Novika capability. All
  # capability classes must be compatible with this module.
  module ICapabilityClass
    # Returns the frontend identifier of this capability class.
    abstract def id : String

    # Returns a short description on what this capability class provides.
    abstract def purpose : String

    # Returns whether this capability class should be enabled automatically.
    abstract def on_by_default? : Bool
  end

  # Instance-side (`include`) interface to a Novika capability.
  # All capability instances must be compatible with this module.
  module ICapability
    # Returns the collection this capability is a part of.
    getter capabilities : CapabilityCollection

    def initialize(@capabilities)
    end

    # Injects the vocabulary of this capability into the *target* block.
    abstract def inject(into target : Block)
  end

  # Merges instance-side and class-side interfaces to a Novika
  # capability. Automatically includes `ICapabilityClass` and
  # `ICapability` for you.
  module Capability
    macro included
      include ICapability
      extend ICapabilityClass
    end
  end

  # A collection of language capability implementations.
  #
  # Capability implementations can indirectly (by id) interact
  # with each other by sharing the capability collection they're
  # members of.
  #
  # ```
  # # (!) Compile with -Dnovika_console
  #
  # caps = CapabilityCollection.new
  #
  # # Add capability classes:
  # caps << Capabilities::Impl::Essential
  # caps << Capabilities::Impl::System
  # caps << Capabilities::Impl::Console
  #
  # # Enable capabilities. At this point you kinda don't know
  # # which implementation is used under the hood, so you
  # # need to refer to the capability by its id.
  # caps.enable("essential")
  # caps.enable("system")
  # caps.enable("console")
  #
  # block = Block.new(caps.block)
  # block.slurp("console:on 1000 nap console:off")
  #
  # Engine.exhaust(block, caps)
  # ```
  class CapabilityCollection
    # Returns the *capability block*: a block managed by this
    # collection, which includes the vocabulary injected by
    # the enabled capabilities.
    getter block : Block

    def initialize(parent : Block? = nil)
      @block = Block.new(parent)
      @classes = {} of String => ICapabilityClass
      @objects = {} of String => Capability
      @libraries = {} of String => Library
    end

    # Returns an array of capabilities that are enabled in this
    # collection at the moment.
    def enabled
      @objects.values.map(&.class)
    end

    # Returns whether this collection has the capability with
    # the given *id* enabled.
    def has_capability_enabled?(id : String)
      @objects.has_key?(id)
    end

    # Returns whether this collection includes a capability with
    # the given *id*.
    def has_capability?(id : String)
      @classes.has_key?(id)
    end

    # Returns whether this collection includes a library with
    # the given *id*.
    def has_library?(id : String)
      @libraries.has_key?(id)
    end

    # Enables a capability with the given *id*.
    #
    # To enable a capability means to create an instance of the
    # corresponding implementation class, and use that instance
    # to inject the capability vocabulary into this collection's
    # *capabilities block*, `block`. You can then access `block`
    # and e.g. inherit from it to access the vocabulary of the
    # enabled capabilities.
    #
    # Does nothing if the capability is already enabled.
    # Does nothing if there is no capability with the given id.
    #
    # Returns whether there is a capability with the given *id*.
    def enable(id : String) : Bool
      return true if @objects.has_key?(id)
      return false unless cap = get_capability_class?(id)

      object = cap.new(self)
      object.inject(block)

      @objects[id] = object

      true
    end

    # Enables all capabilities that respond with true when sent
    # `ICapabilityClass#on_by_default?`.
    #
    # For capabilities that respond with false, you'll need to
    # target them explicitly with `enable(id)`, or use `enable_all`
    # instead of `enable_default`.
    #
    # Returns self.
    def enable_default
      @classes.each { |k, v| enable(k) if v.on_by_default? }

      self
    end

    # Enables all capabilities unconditionally.
    #
    # Returns self.
    def enable_all
      @classes.each_key { |k| enable(k) }

      self
    end

    # Returns the instance of the given capability class *cls*,
    # if such instance can be found in this collection. Otherwise,
    # returns nil.
    def []?(cls : T.class) : T? forall T
      @objects[cls.id]?.try &.as(T)
    end

    # Returns the library with the given *id*. Returns nil if there
    # is no such library in this collection.
    def get_library?(id : String)
      @libraries[id]?
    end

    # Returns the capability class with the given *id*. Returns nil
    # if there is no such capability class in this collection.
    def get_capability_class?(id : String)
      @classes[id]?
    end

    @load_library_callbacks = [] of String -> Library?

    # Subscribes *callback* to library load requests, so that
    # whenever the runtime needs a library, *callback* gets a
    # chance to be invoked and load it.
    #
    # *callback* is only going to be invoked if all previously
    # defined callbacks failed (returned nil).
    #
    # *callback* should return a `Library` if it successfully
    # loaded it; otherwise, it should return nil.
    def on_load_library?(callback : String -> Library?)
      @load_library_callbacks << callback
    end

    # :ditto:
    def on_load_library?(&callback : String -> Library?)
      on_load_library?(callback)
    end

    # Tries to load a library (aka shared object) with the given
    # *id*. Returns the resulting `Library` object, or nil.
    #
    # The library object is cached: further calls to `load_library?`
    # and `get_library?` will return that library object.
    def load_library?(id : String) : Library?
      @libraries.fetch(id) do
        @load_library_callbacks.each do |callback|
          if library = callback.call(id)
            return @libraries[id] = library
          end
        end
      end
    end

    # Yields the capability instance of the given capability
    # class *cls* to the block, if such instance can be found
    # in this collection.
    #
    # Returns the result of the block, or nil.
    def fetch(cls : T.class, & : T -> U) : U? forall T, U
      if impl = self[cls]?
        yield impl
      end
    end

    # Adds a capability class *cls* to this collection.
    def <<(cls : ICapabilityClass)
      @classes[cls.id] = cls
    end

    # Adds a *library* to this collection. Overwrites any previous
    # library with the same id.
    def <<(library : Library)
      @libraries[library.id] = library
    end

    # Copies this capability collection.
    #
    # * This collection shares library load callbacks (themselves,
    #   *not* the list of them) with the returned collection.
    #
    # * This collection shares FFI `Library` instances with the
    #   returned one, by reference.
    #
    # * This collection shares capability block parent (see `new`)
    #   with the returned one, by reference.
    #
    # Everything else is copied or created anew.
    def copy : CapabilityCollection
      copy = CapabilityCollection.new

      @classes.each_value { |cls| copy << cls }
      @objects.each_key { |id| copy.enable(id) }
      @libraries.each_value { |library| copy << library }

      @load_library_callbacks.each do |callback|
        copy.on_load_library?(callback)
      end

      copy
    end

    # Creates a capability collection, and adds capabilities that
    # are on by default. Doesn't enable any. Returns the resulting
    # capability collection.
    def self.with_default
      caps = CapabilityCollection.new
      available.each do |cap|
        next unless cap.on_by_default?
        caps << cap
      end
      caps
    end

    # Creates a capability collection, and adds *all* available
    # capabilities (see `CapabilityCollection.available`). Does
    # not enable any of them.
    #
    # Returns the resulting capability collection.
    def self.with_available
      caps = CapabilityCollection.new
      available.each { |cap| caps << cap }
      caps
    end

    # Lists *all* available (registered) capability classes.
    #
    # For a capability class to be registered (available), it
    # should be the last subclass of a `Capability` includer
    # (subclass depth is irrelevant), or have no subclasses
    # and directly include `Capability`.
    def self.available : Array(ICapabilityClass)
      {% begin %}
        [{% for capability in Capability.includers %}
          {% subclasses = capability.all_subclasses %}
          {% if !capability.abstract? && subclasses.empty? %}
            {{capability}},
          {% elsif subclass = subclasses.reject(&.abstract?).last %}
            {{subclass}},
          {% end %}
        {% end %}] of ICapabilityClass
      {% end %}
    end
  end
end
