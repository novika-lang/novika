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
    # Returns the bundle this capability is a part of.
    getter bundle : Bundle

    def initialize(@bundle)
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
  # with each other via bundles.
  #
  # ```
  # # (!) Compile with -Dnovika_console
  #
  # bundle = Bundle.new
  #
  # # Add capability classes:
  # bundle << Capabilities::Impl::Essential
  # bundle << Capabilities::Impl::System
  # bundle << Capabilities::Impl::Console
  #
  # # Enable capabilities. At this point you kinda don't know
  # # which implementation is used under the hood, so you
  # # need to refer to the capability by its id.
  # bundle.enable("essential")
  # bundle.enable("system")
  # bundle.enable("console")
  #
  # block = Block.new(bundle.bb)
  # block.slurp("console:on 1000 nap console:off")
  #
  # Engine.exhaust(block, bundle)
  # ```
  class Bundle
    # Returns the bundle block: a block managed by this bundle,
    # which includes all words injected by capabilities.
    getter bb : Block

    def initialize(parent : Block? = nil)
      @bb = Block.new(parent)
      @classes = {} of String => ICapabilityClass
      @objects = {} of String => Capability
      @libraries = {} of String => Library
    end

    # Returns an array of capabilities that are enabled in this
    # bundle at the moment.
    def enabled
      @objects.values.map(&.class)
    end

    # Returns whether this bundle has the capability with the
    # given *id* enabled.
    def has_capability_enabled?(id : String)
      @objects.has_key?(id)
    end

    # Returns whether this bundle includes a capability with
    # the given *id*.
    def has_capability?(id : String)
      @classes.has_key?(id)
    end

    # Returns whether this bundle includes a library with the
    # given *id*.
    def has_library?(id : String)
      @libraries.has_key?(id)
    end

    # Enables a capability with the given *id*.
    #
    # To enable a capability means to create an instance of the
    # corresponding implementation class, and use that instance
    # to inject the capability vocabulary into the bundle block,
    # `bb`. You can then access `bb` and inherit from it.
    #
    # Does nothing if the capability is already enabled.
    #
    # Does nothing if there is no capability with the given id.
    #
    # Returns whether there is a capability with the given *id*.
    def enable(id : String) : Bool
      return true if @objects.has_key?(id)
      return false unless cap = get_capability_class?(id)

      object = cap.new(self)
      object.inject(bb)

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
    # if such instance can be found in this bundle. Otherwise,
    # returns nil.
    def []?(cls : T.class) : T? forall T
      @objects[cls.id]?.try &.as(T)
    end

    # Returns the library with the given *id*. Returns nil if there
    # is no such library in this bundle.
    def get_library?(id : String)
      @libraries[id]?
    end

    # Returns the capability class with the given *id*. Returns nil
    # if there is no such capability class in this bundle.
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
    def on_load_library?(&callback : String -> Library?)
      @load_library_callbacks << callback
    end

    # Tries to load a library (aka shared object) with the given
    # *id*. Returns the resulting `Library` object, or nil. The
    # library object is cached: further calls to `load_library?`
    # and `get_library?` will return that library object.
    #
    # Usually, bundle is used as a dumb-ish container for capabilities
    # and libraries that were loaded beforehand, by the frontend of
    # choice. `load_library?` breaks this habit, and allows bundle
    # users to request new stuff from the frontend at runtime.
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
    # in this bundle.
    #
    # Returns the result of the block, or nil.
    def fetch(cls : T.class, & : T -> U) : U? forall T, U
      if impl = self[cls]?
        yield impl
      end
    end

    # Adds a capability class *cls* to this bundle.
    def <<(cls : ICapabilityClass)
      @classes[cls.id] = cls
    end

    # Adds a *library* to this bundle. Overwrites any previous
    # library with the same id.
    def <<(library : Library)
      @libraries[library.id] = library
    end

    # Creates a bundle, and adds capabilities that are on by
    # default. Doesn't enable any. Returns the resulting bundle.
    def self.with_default
      bundle = Bundle.new
      capabilities.each do |cap|
        if cap.on_by_default?
          bundle << cap
        end
      end
      bundle
    end

    # Creates a bundle, and adds *all* registered capabilities
    # (see `Bundle.capabilities`). Doesn't enable any. Returns
    # the resulting bundle.
    def self.with_all
      bundle = Bundle.new
      capabilities.each do |cap|
        bundle << cap
      end
      bundle
    end

    # Lists *all* registered (available) capability classes.
    #
    # For a capability class to be registered (available), it
    # should be the last subclass of a `Capability` includer
    # (subclass depth is irrelevant), or have no subclasses
    # and directly include `Capability`.
    def self.capabilities : Array(ICapabilityClass)
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
