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
  # Engine.exhaust(block)
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
    end

    # Returns an array of feature classes that this bundle
    # has enabled at the moment.
    def enabled
      @objects.values.map(&.class)
    end

    # Returns whether this bundle includes a feature class
    # with the given *id*.
    def includes?(id : String)
      @classes.has_key?(id)
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
      return false unless feature = @classes[id]?

      object = feature.new(self)
      object.inject(bb)

      @objects[id] = object

      true
    end

    # Enables all features that respond with true when sent
    # `IFeatureClass#on_by_default?`.
    #
    # For features that respond with false, you'll need to
    # explicitly `enable(id)` them.
    def enable_default
      @classes.each { |k, v| enable(k) if v.on_by_default? }
    end

    # Returns the feature instance of the given *feature* class,
    # if one can be found in this bundle. Otherwise, returns nil.
    def []?(feature : T.class) : T? forall T
      @objects[feature.id]?.try &.as(T)
    end

    # Adds a feature class to this bundle.
    def <<(feature : IFeatureClass)
      @classes[feature.id] = feature
    end

    # Creates a bundle, adds and enables features that are on
    # by default. Returns the resulting bundle.
    def self.default
      bundle = Bundle.new
      features.each do |feature|
        if feature.on_by_default?
          bundle << feature
        end
      end
      bundle.enable_default
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
