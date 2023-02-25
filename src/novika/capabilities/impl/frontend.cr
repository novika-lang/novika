module Novika::Capabilities::Impl
  class Frontend < IFrontend
    def version(engine) : Quote
      Quote.new(Novika::VERSION)
    end

    def capabilities(engine) : Block
      list = Block.new
      bundle.enabled.each do |klass|
        list.add Quote.new(klass.id)
      end
      list
    end
  end
end
