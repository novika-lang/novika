module Novika
  # Class-side (`extend`) interface to a Novika package. All
  # package classes must be compatible with this module.
  module IPackageClass
    # Returns the frontend identifier of this package.
    abstract def id : String

    # Returns a short description on what this package provides.
    abstract def purpose : String

    # Returns whether this package should be enabled automatically.
    abstract def on_by_default? : Bool
  end

  # Instance-side (`include`) interface to a Novika package.
  # All package instances must be compatible with this module.
  module IPackage
    # Returns the bundle this package is a part of.
    getter bundle : Bundle

    def initialize(@bundle)
    end

    # Injects the vocabulary of this package into the *target* block.
    abstract def inject(into target : Block)
  end

  # A merge of instance-side and class-side interfaces to a
  # Novika package. Auto-includes `IPackageClass` and `IPackage`
  # for you.
  module Package
    macro included
      include IPackage
      extend IPackageClass
    end
  end

  # A bundle of package classes (sometimes also called package
  # implementations) and instances of those classes.
  #
  # Package instances can talk with each other with the help
  # of bundles.
  #
  # Usage example:
  #
  # ```
  # bundle = Bundle.new
  #
  # # Add package classes (package implementations):
  # bundle << Packages::Essential
  # bundle << Packages::Impl::System
  # bundle << Packages::Impl::Console
  #
  # # Enable packages. At this point you kinda don't know which
  # # implementation are used under the hood, so you need to refer
  # # to the packages by their ids.
  # bundle.enable("essential")
  # bundle.enable("system")
  # bundle.enable("console")
  #
  # block = Block.new(bundle.bb)
  # block.slurp("console:on 1000 nap console:off")
  #
  # engine = Engine.new
  # engine.schedule(stack: Block.new, form: block)
  # engine.exhaust
  # ```
  class Bundle
    # Returns the bundle block: a block managed by this bundle,
    # which includes all words injected by this bundle's package
    # instances.
    getter bb : Block

    def initialize(parent : Block? = nil)
      @bb = Block.new(parent)
      @classes = {} of String => IPackageClass
      @objects = {} of String => Package
    end

    # Returns an array of package classes that this bundle
    # has enabled at the moment.
    def enabled
      @objects.values.map(&.class)
    end

    # Returns whether this bundle includes a package class
    # with the given *id*.
    def includes?(id : String)
      @classes.has_key?(id)
    end

    # Enables a package class with the given *id*.
    #
    # To enable a package means to create a package instance,
    # and use that instance to inject the package vocabulary
    # into the bundle block, `bb`. You can then access `bb`
    # and inherit from it.
    #
    # Does nothing if the package class is already enabled.
    # Does nothing if there is no package class with the given id.
    #
    # Returns whether there is a package with the given *id*.
    def enable(id : String) : Bool
      return true if @objects.has_key?(id)
      return false unless package = @classes[id]?

      object = package.new(self)
      object.inject(bb)

      @objects[id] = object

      true
    end

    # Enables all packages that respond to `IPackageClass#on_by_default?`
    # with true. For packages that do not, you'll need to do
    # a manual call to `enable(id)`.
    def enable
      @classes.each { |k, v| enable(k) if v.on_by_default? }
    end

    # Returns the package instance of the given *package* class,
    # if one can be found in this bundle. Otherwise, returns nil.
    def []?(package : T.class) : T? forall T
      @objects[package.id]?.try &.as(T)
    end

    # Adds a package class to this bundle.
    def <<(package : IPackageClass)
      @classes[package.id] = package
    end

    # Lists *all* registered (available) package classes.
    #
    # For a package class to be registered (available), it
    # should be the last subclass of a `Package` includer
    # (subclass depth is irrelevant), or have no subclasses
    # and directly include `Package`.
    def self.available : Array(IPackageClass)
      {% begin %}
        [{% for package in Package.includers %}
          {% subclasses = package.all_subclasses %}
          {% if !package.abstract? && subclasses.empty? %}
            {{package}},
          {% else %}
            {{subclasses.reject(&.abstract?).last}},
          {% end %}
        {% end %}] of IPackageClass
      {% end %}
    end
  end
end
