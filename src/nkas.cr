require "./common"
require "./novika"

module Novika::Frontend::Nkas
  extend self

  # Appends information about the tool to *io*.
  def help(io)
    io << <<-HELP
    nkas - Novika image assembler for Novika #{Novika::VERSION}

    Syntax:

      nkas [switches] [runnables] <path/to/output/image.nki>

    Switches:

      -c  Compress with (default: do not compress)
        b:  Brotli
          f Compress quickly (fast)!
          b Compress thoroughly (best)!
        g:  Gzip
          f Compress quickly (fast)!
          b Compress thoroughly (best)!

    Example:

      $ nkas -cb:b repl repl.nki
      Ok  Bundle <yours-may-differ>
      Ok  Bundle <yours-may-differ>
      Ok  Bundle <yours-may-differ>
      Ok  Bundle <yours-may-differ>
      Ok  Bundle <yours-may-differ>
      Ok  Write repl.nki

      $ nki repl.nki
      [starts the repl]

    Runnables:

      In runnable treatment, this tool is fully compatible with
      the command-line frontend.

    Purpose:

      A handy tool for packing Novika images e.g. to transfer
      them over the network or distribute. Novika images can
      be unpacked by the 'nki' tool which is a bit smaller
      than the Novika command-line frontend, if distribution
      size is what matters for you.

    HELP
  end

  def start(args = ARGV)
    if args.size < 2
      help(STDOUT)
      exit(0)
    end

    imagepath = nil
    compression = Novika::Image::CompressionType::None

    runnables = ARGV.map_with_index do |arg, index|
      if index == ARGV.size - 1 && arg.ends_with?(".nki")
        imagepath = arg
        next
      end

      if arg =~ /-c([bg]):([fb])/
        case {$1, $2}
        when {"b", "f"} then compression = Novika::Image::CompressionType::BrotliFast
        when {"b", "b"} then compression = Novika::Image::CompressionType::BrotliBest
        when {"g", "f"} then compression = Novika::Image::CompressionType::GzipFast
        when {"g", "b"} then compression = Novika::Image::CompressionType::GzipBest
        else
          Frontend.errln("invalid compression option: #{arg}")
          exit(1)
        end
        next
      end

      arg
    end.compact

    unless imagepath
      Frontend.errln("Please provide a 'path/to/image.nki' as the last argument.")
      Frontend.noteln("This'll let us know where to save the image.")
      exit(1)
    end

    bundle = Bundle.with_all
    bundle.enable_default

    resolver = RunnableResolver.new(runnables, bundle)
    unless resolver.resolve?
      help(STDOUT)
      exit(0)
    end

    if resolver.apps.size > 1
      names = resolver.apps.join(", ", &.path.basename)
      Frontend.errln("could not determine which app to pack (given apps: #{names})")
      Frontend.noteln("pick one or, if this doesn't seem right, create an issue!")
      exit(1)
    end

    unless resolver.unknowns.empty?
      resolver.unknowns.each do |arg|
        Frontend.errln("could not resolve runnable #{arg.colorize.bold}: it's not a file, directory, app, or feature")
      end
      exit(1)
    end

    resolver.features.each { |feature| bundle.enable(feature) }

    # Flatten to paths in proper order!
    paths = [] of Path

    resolver.folders.each do |folder|
      folder.entry.try { |entry| paths << entry }
      paths.concat(folder.files)
    end

    resolver.files.each do |file|
      paths << file
    end

    resolver.apps.each do |app|
      app.entry.try { |entry| paths << entry }
      paths.concat(app.files)
    end

    # Slurp into One Big Block.
    mod = Novika::Block.new
    paths.each do |file|
      Frontend.wait("Bundling #{file}...", ok: "Bundled #{file}") do
        mod.slurp(File.read(file))
      end
    end

    # Write the image.
    File.open(img = ARGV[-1], "w") do |file|
      Frontend.wait("Writing image #{img}...", ok: "Wrote image #{img}") do
        file.write_bytes(Novika::Image.new(mod, bundle, compression))
      end
    end
  end
end

Novika::Frontend::Nkas.start
