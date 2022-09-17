module Novika::Features
  abstract class IFrontend
    include Feature

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

    # Returns a list block of features provided by the frontend.
    abstract def features(engine) : Block

    def inject(into target : Block)
      target.at("novika:version", <<-END
      ( -- Vq ): leaves Version of the frontend as a quote.
      END
      ) { |engine| version(engine).push(engine) }

      target.at("novika:features", <<-END
      ( -- Fb ): lists the ids of features provided by the
       frontend in Feature block.

      >>> novika:features
      === [ 'essential' 'colors' 'console' | ] (yours may differ)
      END
      ) { |engine| features(engine).push(engine) }
    end
  end
end
