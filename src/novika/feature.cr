module Novika
  # Class-side (`extend`) interface to a Novika feature. All
  # feature classes must be compatible with this module.
  module IFeatureClass
    # Returns the frontend identifier of this feature.
    abstract def id : String

    # Returns a short description on what this feature provides.
    abstract def purpose : String

    # Returns whether this feature should be enabled automatically.
    abstract def on_by_default? : Bool
  end

  # Instance-side (`include`) interface to a Novika feature.
  # All feature instances must be compatible with this module.
  module IFeature
    # Returns the bundle this feature is a part of.
    getter bundle : Bundle

    def initialize(@bundle)
    end

    # Injects the vocabulary of this feature into the *target* block.
    abstract def inject(into target : Block)
  end

  # A merge of instance-side and class-side interfaces to a
  # Novika feature. Auto-includes `IFeatureClass` and `IFeature`
  # for you.
  module Feature
    macro included
      include IFeature
      extend IFeatureClass
    end
  end

  # A bundle of feature classes (sometimes also called feature
  # implementations) and instances of those classes.
  #
  # Feature instances can talk with each other with the help
  # of bundles.
  #
  # Usage example:
  #
  # ```
  # # (!) Compile with -Dnovika_console
  #
  # bundle = Bundle.new
  #
  # # Add feature classes (feature implementations):
  # bundle << Features::Impl::Essential
  # bundle << Features::Impl::System
  # bundle << Features::Impl::Console
  #
  # # Enable features. At this point you kinda don't know
  # # which implementation is used under the hood, so you
  # # need to refer to the feature by its ID.
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
    # which includes all words injected by this bundle's feature
    # instances.
    getter bb : Block

    def initialize(parent : Block? = nil)
      @bb = Block.new(parent)
      @classes = {} of String => IFeatureClass
      @objects = {} of String => Feature
      @libraries = {} of String => Library
    end

    # Returns an array of feature classes that are enabled
    # in this bundle at the moment.
    def enabled
      @objects.values.map(&.class)
    end

    # Returns whether this bundle has the feature class with
    # the given *id* enabled.
    def has_feature_enabled?(id : String)
      @objects.has_key?(id)
    end

    # Returns whether this bundle includes a feature class
    # with the given *id*.
    def has_feature?(id : String)
      @classes.has_key?(id)
    end

    # Returns whether this bundle includes a library with the
    # given *id*.
    def has_library?(id : String)
      @libraries.has_key?(id)
    end

    # Enables a feature class with the given *id*.
    #
    # To enable a feature means to create a feature instance,
    # and use that instance to inject the feature vocabulary
    # into the bundle block, `bb`. You can then access `bb`
    # and inherit from it.
    #
    # Does nothing if the feature class is already enabled.
    # Does nothing if there is no feature class with the given id.
    #
    # Returns whether there is a feature with the given *id*.
    def enable(id : String) : Bool
      return true if @objects.has_key?(id)
      return false unless feature = get_feature_class?(id)

      object = feature.new(self)
      object.inject(bb)

      @objects[id] = object

      true
    end

    # Enables all features that respond with true when sent
    # `IFeatureClass#on_by_default?`.
    #
    # For features that respond with false, you'll need to
    # target them explicitly with `enable(id)`, or use
    # `enable_all` instead of `enable_default`.
    #
    # Returns self.
    def enable_default
      @classes.each { |k, v| enable(k) if v.on_by_default? }

      self
    end

    # Enables all features unconditionally.
    #
    # Returns self.
    def enable_all
      @classes.each_key { |k| enable(k) }

      self
    end

    # Returns the feature instance of the given *feature* class,
    # if one can be found in this bundle. Otherwise, returns nil.
    def []?(feature : T.class) : T? forall T
      @objects[feature.id]?.try &.as(T)
    end

    # Returns the library with the given *id*. Returns nil if there
    # is no such library in this bundle.
    def get_library?(id : String)
      @libraries[id]?
    end

    # Returns the feature class with the given *id*. Returns nil
    # if there is no such feature class in this bundle.
    def get_feature_class?(id : String)
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
    # Usually, bundle is used as a dumb-ish container for features
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

    # Yields the feature instance of the given *feature* class
    # to the block, if one can be found in this bundle.
    #
    # Returns the result of the block, or nil.
    def fetch(feature : T.class, & : T -> U) : U? forall T, U
      if impl = self[feature]?
        yield impl
      end
    end

    # Adds a feature class to this bundle.
    def <<(feature : IFeatureClass)
      @classes[feature.id] = feature
    end

    # Adds a *library* to this bundle. Overwrites any previous
    # library with the same id.
    def <<(library : Library)
      @libraries[library.id] = library
    end

    # Creates a bundle, and adds features that are on by
    # default. Doesn't enable any. Returns the resulting
    # bundle.
    def self.with_default
      bundle = Bundle.new
      features.each do |feature|
        if feature.on_by_default?
          bundle << feature
        end
      end
      bundle
    end

    # Creates a bundle, and adds *all* registered features
    # (see `Bundle.features`). Doesn't enable any. Returns
    # the resulting bundle.
    def self.with_all
      bundle = Bundle.new
      features.each do |feature|
        bundle << feature
      end
      bundle
    end

    # Lists *all* registered (available) feature classes.
    #
    # For a feature class to be registered (available), it
    # should be the last subclass of a `Feature` includer
    # (subclass depth is irrelevant), or have no subclasses
    # and directly include `Feature`.
    def self.features : Array(IFeatureClass)
      {% begin %}
        [{% for feature in Feature.includers %}
          {% subclasses = feature.all_subclasses %}
          {% if !feature.abstract? && subclasses.empty? %}
            {{feature}},
          {% elsif subclass = subclasses.reject(&.abstract?).last %}
            {{subclass}},
          {% end %}
        {% end %}] of IFeatureClass
      {% end %}
    end
  end
end
