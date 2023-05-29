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
      [starts the repl; the following REPL session demonstates
       the use of the '-c' switch]
      >>> 100 $: x
      >>> 200 $: y
      >>> 'repl-save00.nki' disk:touch
      >>> conts nki:captureAll
      "Note! It is important to write to disk in the next REPL
       prompt, because otherwise, nki:captureAll will capture
       before pushing the image byteslice, and before your
       write command. In short, this leaves your REPL save in
       an 'unexpected' state."
      >>> 'repl-save00.nki' disk:write
      <Ctrl-D>
      $ nki -c repl-save00.nki
      >>> x y + echo
      300

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
    caps = Novika::CapabilityCollection.with_available

    filepath = Path[ARGV[-1]].expand
    filedir = filepath.parent

    caps.on_load_library? do |id|
      paths = {filedir, filedir / "lib"}

      {% if flag?(:windows) %}
        paths = paths.flat_map { |path| [path / "#{id}.dll", path / "lib#{id}.dll"] }
      {% elsif flag?(:unix) %}
        paths = paths.flat_map { |path| [path / "#{id}.so", path / "lib#{id}.so"] }
      {% else %}
        next
      {% end %}

      path = paths.each { |path| break path if File.exists?(path) }

      Library.new(id, path) if path
    end

    File.open(filepath, "r") do |infile|
      image = infile.read_bytes(Novika::Image)
      block = image.to_block(caps)
      engine = Novika::Engine.push(caps)

      if conts
        engine.conts = block
        engine.exhaust
      else
        block.parent = Block.new(caps.block)
        block.at(Word.new("__path__"), Quote.new(filedir.to_s))
        block.at(Word.new("__file__"), Quote.new(filepath.to_s))
        block.at(Word.new("__runtime__"), Quote.new("nki"))
        engine.schedule!(block, stack: Block.new)
        engine.exhaust
      end
    rescue error : Novika::Error
      error.report(STDERR)
    rescue error : BinData::CustomException
      Frontend.errln("This file doesn't seem like a valid Novika image: '#{ARGV[-1]}'")
      exit(1)
    end
  end
end

Novika::Frontend::Nki.start
