module Novika::Capabilities
  abstract class IFrontend
    include Capability

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

    # Returns a list block of capabilities provided by the frontend.
    abstract def capabilities(engine) : Block

    def inject(into target : Block)
      target.at("novika:version", <<-END
      ( -- Vq ): leaves Version of the frontend as a quote.
      END
      ) { |engine, stack| version(engine).onto(stack) }

      target.at("novika:capabilities", <<-END
      ( -- Lb ): lists the ids of capabilities provided by the
       frontend in List block.

      ```
      "Yours may differ!"
      novika:capabilities leaves: [ [ 'essential' 'colors' 'console' ] ]
      ```
      END
      ) { |engine, stack| capabilities(engine).onto(stack) }
    end
  end
end
