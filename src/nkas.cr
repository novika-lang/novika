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
      Ok  Bundled <yours-may-differ>
      Ok  Bundled <yours-may-differ>
      Ok  Bundled <yours-may-differ>
      Ok  Bundled <yours-may-differ>
      Ok  Bundled <yours-may-differ>
      Ok  Wrote repl.nki

      $ nki repl.nki
      [starts the repl]

    Runnables:

      In runnable treatment, this tool is fully compatible with
      the command-line frontend.

    Purpose:

      A handy tool for packing Novika images e.g. to transfer
      them over the network, or distribute. Novika images can
      be run by the 'nki' tool which is a bit smaller feature-
      wise than the Novika command-line frontend.

    HELP
  end

  def start(args = ARGV, cwd = Path[ENV["NOVIKA_CWD"]? || Dir.current])
    Colorize.enabled = Novika.colorful?

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
      Frontend.noteln("This will let me know where to save the image.")
      exit(1)
    end

    resolver = RunnableResolver.new(cwd, runnables)

    resolver.on_permissions_gets do |string|
      print string, " "
      gets
    end

    resolver.on_permissions_print do |string|
      print string
    end

    resolver.after_permissions do |hook|
      designations = hook.designations
      prefix = designations.size > 1 # Mixed environments in args/cwd

      designations.each do |designation|
        # Slurp into One Big Block.
        mod = Novika::Block.new(designation.caps.block)

        Frontend.wait("Bundling #{ARGV[-1]} (#{designation.label})...\n", ok: "Bundled #{ARGV[-1]} (#{designation.label})") do
          designation.slurp(mod)
        end

        # Write the image.
        File.open(img = prefix ? "#{Path[ARGV[-1]].stem}.#{designation.label}.nki" : ARGV[-1], "w") do |file|
          Frontend.wait("Writing image #{img}...\n", ok: "Wrote image #{img}") do
            file.write_bytes(Novika::Image.new(mod, designation.caps, compression))
          end
        end
      end
    end

    unless resolver.resolve?
      help(STDOUT)
      exit(0)
    end
  rescue e : Resolver::RunnableError
    e.runnable.backtrace(STDERR, indent: 2) do |io|
      Frontend.err(e.message, io)
    end
    exit(1)
  rescue e : Resolver::ResponseRejectedError
    e.response.each_rejected_runnable do |runnable|
      runnable.backtrace(STDERR, indent: 2) do |io|
        Frontend.err(e.message, io)
      end
    end
    exit(1)
  rescue e : Resolver::MoreThanOneAppError
    e.apps.each do |app|
      app.backtrace(STDERR, indent: 2) do |io|
        Frontend.noteln("could not run this app because it's not the only one", io)
      end
    end

    Frontend.errln(e.message)
    exit(1)
  rescue e : Resolver::ResolverError
    Frontend.errln(e.message)
  end
end

Novika::Frontend::Nkas.start
