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

  # Returns an array of all registered package classes.
  #
  # For your package to be registered, it should be the last
  # subclass of a `Package` includer (subclass depth is irrelevant),
  # or have no subclasses and be a direct `Package` includer.
  def self.packages : Hash(String, IPackageClass)
    # The type of IPackageClass is valid and not at the same
    # time. It really should be Package.class but Crystal
    # refuses to take that.
    #
    # Whether this will shoot back I don't know.
    hash = {} of String => IPackageClass

    {% for package in Package.includers %}
      {% subclasses = package.all_subclasses %}

      {% if !package.abstract? && subclasses.empty? %}
        hash[{{package}}.id] = {{package}}
      {% else %}
        hash[{{package}}.id] = {{subclasses.reject(&.abstract?).last}}
      {% end %}
    {% end %}

    hash
  end
end
