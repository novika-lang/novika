require "./novika"
require "./common"

module Novika::Frontend::Nki
  extend self

  def help(io)
    io << <<-HELP
    nki - Novika image interpreter for Novika #{Novika::VERSION}

    Syntax:

      nki [switches] <path/to/image.nki>

    Switches:

      -c  Interpret image as that of the continuations block

    Example:

      $ nkas -cb:b repl repl.nki
      [assembles the repl]

      $ nki repl.nki
      [starts the repl]

      $ novika console examples/snake.nk
      [play snake, hit Ctrl+S, quit or loose]

      $ nki -c snake-savegame00.nki
      [runs snake exactly like when Ctrl-S was pressed!]

    Purpose:

      A tool aimed for being carried along with a Novika image,
      to be able to run/load it.

    HELP
  end

  def start
    if ARGV.size < 1
      help(STDOUT)
      exit(0)
    end

    conts = ARGV.delete("-c")
    bundle = Novika::Bundle.with_all

    File.open(ARGV[-1], "r") do |infile|
      image = infile.read_bytes(Novika::Image)
      block = image.to_block(bundle)

      if conts
        engine = Novika::Engine.new(bundle)
        engine.conts = block.not_nil!
        engine.exhaust
      else
        block.not_nil!.parent = bundle.bb
        Novika::Engine.exhaust!(block.not_nil!, bundle: bundle)
      end
    rescue error : Novika::Error
      error.report(STDERR)
    rescue error : BinData::ReadingVerificationException
      Frontend.errln("This file doesn't seem like a valid Novika image: '#{ARGV[-1]}'")
      exit(1)
    end
  end
end

Novika::Frontend::Nki.start
