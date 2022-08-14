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

module Novika
  extend self

  # Represents a folder with Novika files, containing an `entry`
  # file path (if any; e.g., `core.nk` inside a folder named
  # `core`), and paths for all other `files` (if any).
  record Folder, entry : Path? = nil, files = [] of Path

  # Appends help message to *io*.
  def help(io)
    cdir = "directory".colorize.blue
    cpkg = "package".colorize.magenta
    cfile = "file".colorize.green
    on = "on by default".colorize.bold

    io << <<-END
  Welcome to Novika, and thanks for trying it out!

  One or more arguments must be provided for Novika to properly
  pick up what you're trying to run. For instance:

    $ novika     core          console      example.nk
                 ----          -------      ----------
                 a #{cdir}   a #{cpkg}    a #{cfile}

  (1) When you provide a #{cdir}, Novika will run all *.nk
      files in that directory. First, *.nk files in the directory
      itself are run, and then that process is repeated in the
      sub-directories. For any given directory, its entry file,
      <directory-name>.nk (if it exists) is run first.

  (2) Individual #{cfile}s are run after all directories are run.

  (3) There are also a number of builtin #{cpkg}s:
        - kernel (#{on})
        - math (#{on})
        - colors (#{on})
        - console (enables the console API)

  END
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

    pkgs = [
      Packages::Kernel.new,
      Packages::Math.new,
      Packages::Colors.new,
    ] of Package
    files = [] of Path
    folders = {} of Path => Folder

    engine = Engine.new
    pkgblock = Block.new
    toplevel = Block.new(pkgblock)

    args.each do |arg|
      if pkg = Package[arg]?
        # A package. Add it to our packages list, and continue.
        # Do not duplicate.
        pkgs << pkg.new unless pkgs.any?(pkg)
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

    # Inject all our packages into the package block (just a
    # super-duper toplevel block.).
    pkgs.each &.inject(into: pkgblock)

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
