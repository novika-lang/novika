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

  # Returns an array of all package classes.
  #
  # For your package to be a registered package class, it must
  # include `Package`.
  def self.packages
    {{ Package.includers }}
  end

  # Returns the package class with the given *id*.
  def self.package?(id : String)
    packages.find(&.id.== id)
  end
end
