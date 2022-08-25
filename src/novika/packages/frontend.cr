module Novika::Packages
  abstract class IFrontend
    include Package

    def self.id : String
      "frontend"
    end

    def self.purpose : String
      "exposes information about the language frontend"
    end

    def self.on_by_default? : Bool
      true
    end

    # Returns version of the frontend.
    abstract def version(engine) : Quote

    # Returns a list block of packages provided by the frontend.
    abstract def packages(engine) : Block

    def inject(into target : Block)
      target.at("novika:version", <<-END
      ( -- Vq ): leaves Version of the frontend as a quote.
      END
      ) { |engine| version(engine).push(engine) }

      target.at("novika:packages", <<-END
      ( -- Pb ): lists the ids of packages provided by the
       frontend in Package block.

      >>> novika:packages
      === [ 'kernel' 'colors' 'console' | ] (yours may differ)
      END
      ) { |engine| packages(engine).push(engine) }
    end
  end
end
