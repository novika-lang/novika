require "big"
require "colorize"
require "file_utils"

# Order is important!
require "./novika/forms/form"
require "./novika/errors"
require "./novika/tape"
require "./novika/table"
require "./novika/forms/*"
require "./novika/engine"
require "./novika/package"
require "./novika/packages/*"
require "./novika/packages/impl/*"

module Novika
  extend self

  VERSION = "0.0.1"

  # Represents a folder with Novika files, containing an `entry`
  # file path (if any; e.g., `core.nk` inside a folder named
  # `core`), and paths for all other `files` (if any).
  record Folder, entry : Path? = nil, files = [] of Path

  # Returns whether the output of Novika should be colorful.
  #
  # Whether this will be respected by general Novika code cannot
  # be guaranteed, but it is guaranteed to be respected by the
  # CLI frontend.
  def colorful? : Bool
    STDOUT.tty? && STDERR.tty? && ENV["TERM"]? != "dumb" && !ENV.has_key?("NO_COLOR")
  end

  # Appends help message to *io*.
  def help(io)
    Colorize.enabled = Colorize.enabled?.tap do
      # Contextually enable/disable colors depending on whether
      # the user wants them.
      #
      # Contextually because we don't want to affect `colors`
      # et al.
      Colorize.enabled = colorful?

      cdir = "directory".colorize.blue
      cpkg = "package".colorize.magenta
      cfile = "file".colorize.green
      on = "on by default".colorize.bold

      io << <<-END
  Welcome to Novika, and thanks for trying it out!

  Try reading this, or else you may find yourself slightly confused.

  This is the command-line frontend of Novika. It requires that
  you manually list directories, packages, and files that you
  want to be loaded and/or run. For instance:

    $ novika     core          console      example.nk
                 ----          -------      ----------
                 a #{cdir}   a #{cpkg}    a #{cfile}

  Let's take a look at what you ask this frontend to do when
  you give it such a command:

  (1) Please load (and run) all files in the 'core' #{cdir}
      found in the current working directory, all files in the
      sub-directories of 'core', etc. This saves you from listing
      all files found in core/ by hand via (3).

      The order a directory is processed in is as follows: first,
      <directory-name>.nk file is run (if it exists), then all
      other files are run, then this process is repeated on sub-
      directories (if any).

  (2) Please load the #{cpkg} called 'console'. Packages are
      pre-compiled into this binary, and this CLI frontend has
      control over which packages are going to be available for
      the Novika code that it's going to execute.

      A list of packages you can choose from is shown below. Most
      of them are on by default, so you don't have to do anything,
      but some are not. #{"This is the way you can load a package
    when the code you are running asks for it.".colorize.bold}

  (3) Please load (and run) the #{cfile} called 'example.nk',
      found in the current working directory.

  Most Novika code depends on 'core', which is the language's
  standard library, so you'd almost always have the following
  as the go-to command for running Novika files:

    $ novika core path/to/the/file/you/want/to/run.nk

  Here is a list of #{cpkg}s that were pre-compiled into this binary:

  END

      packages = Bundle.available

      packages.select(&.on_by_default?).each do |pkg|
        io.puts
        io << "- " << pkg.id << " (" << pkg.purpose << "; " << on << ")"
      end

      packages.reject(&.on_by_default?).each do |pkg|
        io.puts
        io << "- " << pkg.id << " (" << pkg.purpose << ")"
      end

      io.puts
    end
  end

  # Recursively visits directories starting at, and including,
  # *root*, and creates `Folder`s for their corresponding paths
  # in *folders*.
  def collect(folders : Hash(Path, Folder), root : Path)
    if File.file?(entry = root / "#{root.stem}.nk")
      folders[root] = folder = Folder.new(entry)
    else
      folders[root] = folder = Folder.new
    end

    Dir.glob(root / "*.nk") do |path|
      unless (path = Path[path]) == entry
        folder.files << path
      end
    end

    Dir.glob(root / "/*/") do |path|
      collect(folders, Path[path])
    end
  end

  # Runs the file at *path* using *engine*. A new block is
  # created for *path*; this block inherits *toplevel*.
  #
  # Words from the new block are imported into *toplevel*
  # after the engine is exhausted. Returns *toplevel*.
  def run(engine : Engine, toplevel : Block, path : Path) : Block
    source = File.read(path)
    stack = Block.new
    block = Block.new(toplevel).slurp(source)
    engine.conts.add Engine.cont(block.to(0), stack)
    engine.exhaust
    toplevel.import!(from: block)
  end

  # Novika command-line frontend entry point.
  def frontend(args : Array(String), cwd = Path[FileUtils.pwd])
    if ARGV.empty?
      help(STDERR)
      exit(1)
    end

    bundle = Bundle.new

    Bundle.available.each { |pkg| bundle << pkg }

    bundle.enable_default

    files = [] of Path
    folders = {} of Path => Folder

    engine = Engine.new
    toplevel = Block.new(bundle.bb)

    args.each do |arg|
      if bundle.includes?(arg)
        bundle.enable(arg)
      elsif File.directory?(arg)
        # Exists and is a directory.
        collect(folders, Path[arg])
      elsif File.file?(arg)
        # Exists and is a file.
        files << Path[arg]
      else
        abort "#{arg.colorize.bold} is not a file, directory, or package avaliable in #{cwd}"
      end
    end

    # Evaluate each folder's entry (if any), then its *.nk files.
    folders.each_value do |folder|
      if entry = folder.entry
        run(engine, toplevel, entry)
      end
      folder.files.each do |file|
        run(engine, toplevel, file)
      end
    end

    # Evaluate the user's files.
    files.each { |file| run(engine, toplevel, file) }
  rescue e : EngineFailure
    e.report(STDERR)
  end
end

{% if flag?(:novika_frontend) %}
  Novika.frontend(ARGV)
{% end %}
