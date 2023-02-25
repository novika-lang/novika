module Novika::Capabilities::Impl
  class Nki
    include Capability

    def self.id : String
      "nki"
    end

    def self.purpose : String
      "exposes words to capture, read, and manipulate Novika images"
    end

    def self.on_by_default? : Bool
      true
    end

    def inject(into target : Block)
      target.at("nki:toBlock", <<-END
      ( Bf -- B ): leaves Block for the given Byteslice form,
       assumed to contain a well-formed Novika image created
       with `nki:captureAll`, `nki:captureNeighborhood`, or
       otherwise. Dies if Byteslice form is an invalid Novika
       image, or isn't a Novika image.

      For code example, see `nki:captureNeighborhood`.
      END
      ) do |engine, stack|
        bytes = stack.drop.a(Byteslice)

        begin
          image = bytes.to_io.read_bytes(Image)
        rescue error : BinData::ReadingVerificationException
          bytes.die("apparently, this byteslice is not a Novika image")
        end

        image.to_block(engine.bundle).onto(stack)
      end

      target.at("nki:captureAll", <<-END
      ( B -- Bf ): thoroughly, recursively captures entire
       hierarchy of Block (its parents, prototype, friends,
       tape, and dictionary), and leaves the resulting Novika
       image as a Byteslice form.

      Archives image payload using Gzip, fast.

      If you're a visual type of person, imagine this word and
      all related facilities as a kind of "mold", which carefully,
      in an ordered fashion "fills up" a maze, until all paths
      were explored and all exits found.

      For code example, see `nki:captureNeighborhood`.
      END
      ) do |engine, stack|
        block = stack.drop.a(Block)

        image = Image.new(block, engine.bundle,
          compression: Image::CompressionType::GzipFast,
          mode: CaptureMode::CaptureAll,
        )

        Byteslice.new(&.write_bytes(image)).onto(stack)
      end

      target.at("nki:captureNeighborhood", <<-END
      ( B -- Bf ): like `nki:captureAll`, but rather than
       capturing all reachable blocks, captures only Block's
       neighborhood. Leaves the resulting Byteslice form.

      Archives image payload using Gzip, fast.

      We store each block in Block's tape and dictionary in
      a list, then ask that block to do the same. When recursion
      finishes, the resulting list is called *block neighborhood*.

      Parent, friends, and prototype of the given block are
      reconstructed *if and only if they are in the block
      neighborhood*.

      ```
      [ 1 2 3 ] nki:captureNeighborhood $: imgN

      imgN toQuote leaves: '[byteslice, consists of 111 byte(s)]' "yours may differ!"
      imgN nki:toBlock leaves: [ [ 1 2 3 ] ]

      "As opposed to nki:captureAll, which will capture EVERYTHING
       it can reach:"
      [ 1 2 3 ] nki:captureAll $: imgA

      imgA toQuote leaves: '[byteslice, consists of 38298 byte(s)]' "yours may differ!"

      "Note: [ 1 2 3 ] lives in a parallel universe now, with
       its own friends, prototypes, toplevel block, and so on!
       It doesn't have any links whatsoever to the whoever-it-was
       that called nki:captureAll!"
      imgA nki:toBlock leaves: [ [ 1 2 3 ] ]
      ```
      END
      ) do |engine, stack|
        block = stack.drop.a(Block)

        image = Image.new(block, engine.bundle,
          compression: Image::CompressionType::GzipFast,
          mode: CaptureMode::CaptureNeighborhood,
        )

        Byteslice.new(&.write_bytes(image)).onto(stack)
      end

      target.at("nki:captureAllRaw", <<-END
      ( B -- Bf ): same as `nki:captureAll`, but doesn't archive
       image payload. May yield very large Byteslice forms.
      END
      ) do |engine, stack|
        block = stack.drop.a(Block)

        image = Image.new(block, engine.bundle,
          compression: Image::CompressionType::None,
          mode: CaptureMode::CaptureAll,
        )

        Byteslice.new(&.write_bytes(image)).onto(stack)
      end

      target.at("nki:captureNeighborhoodRaw", <<-END
      ( B -- Bf ): same as `nki:captureNeighborhood`, but doesn't
       archive image payload. May yield large Byteslice forms.
      END
      ) do |engine, stack|
        block = stack.drop.a(Block)

        image = Image.new(block, engine.bundle,
          compression: Image::CompressionType::None,
          mode: CaptureMode::CaptureNeighborhood,
        )

        Byteslice.new(&.write_bytes(image)).onto(stack)
      end

      target.at("nki:captureAllGzipBest", <<-END
      ( B -- Bf ): same as `nki:captureAll`, but archives image
       payload using Gzip, best.
      END
      ) do |engine, stack|
        block = stack.drop.a(Block)

        image = Image.new(block, engine.bundle,
          compression: Image::CompressionType::GzipBest,
          mode: CaptureMode::CaptureAll,
        )

        Byteslice.new(&.write_bytes(image)).onto(stack)
      end

      target.at("nki:captureNeighborhoodGzipBest", <<-END
      ( B -- Bf ): same as `nki:captureNeighborhood`, but
       archives image payload using Gzip, best.
      END
      ) do |engine, stack|
        block = stack.drop.a(Block)

        image = Image.new(block, engine.bundle,
          compression: Image::CompressionType::GzipBest,
          mode: CaptureMode::CaptureNeighborhood,
        )

        Byteslice.new(&.write_bytes(image)).onto(stack)
      end

      target.at("nki:captureAllBrotliFast", <<-END
      ( B -- Bf ): same as `nki:captureAll`, but archives image
       payload using Brotli, fast.
      END
      ) do |engine, stack|
        block = stack.drop.a(Block)

        image = Image.new(block, engine.bundle,
          compression: Image::CompressionType::BrotliFast,
          mode: CaptureMode::CaptureAll,
        )

        Byteslice.new(&.write_bytes(image)).onto(stack)
      end

      target.at("nki:captureNeighborhoodBrotliFast", <<-END
      ( B -- Bf ): same as `nki:captureNeighborhood`, but
       archives image payload using Brotli, fast.
      END
      ) do |engine, stack|
        block = stack.drop.a(Block)

        image = Image.new(block, engine.bundle,
          compression: Image::CompressionType::BrotliFast,
          mode: CaptureMode::CaptureNeighborhood,
        )

        Byteslice.new(&.write_bytes(image)).onto(stack)
      end

      target.at("nki:captureAllBrotliBest", <<-END
      ( B -- Bf ): same as `nki:captureAll`, but archives image
       payload using Brotli, best.
      END
      ) do |engine, stack|
        block = stack.drop.a(Block)

        image = Image.new(block, engine.bundle,
          compression: Image::CompressionType::BrotliBest,
          mode: CaptureMode::CaptureAll,
        )

        Byteslice.new(&.write_bytes(image)).onto(stack)
      end

      target.at("nki:captureNeighborhoodBrotliBest", <<-END
      ( B -- Bf ): same as `nki:captureNeighborhood`, but
       archives image payload using Brotli, best.
      END
      ) do |engine, stack|
        block = stack.drop.a(Block)

        image = Image.new(block, engine.bundle,
          compression: Image::CompressionType::BrotliBest,
          mode: CaptureMode::CaptureNeighborhood,
        )

        Byteslice.new(&.write_bytes(image)).onto(stack)
      end
    end
  end
end
