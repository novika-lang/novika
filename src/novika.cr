require "big"
require "csv"
require "colorize"

# Order is important!
require "./novika/forms/form"
require "./novika/scissors"
require "./novika/classifier"
require "./novika/error"
require "./novika/tape"
require "./novika/dict"
require "./novika/forms/*"
require "./novika/engine"
require "./novika/feature"
require "./novika/features/*"
require "./novika/features/impl/*"

module Novika
  extend self

  VERSION = "0.0.5"

  # Represents a folder with Novika files, containing an `entry`
  # file path (if any; e.g., `core.nk` inside a folder named
  # `core`), and paths for all other `files` (if any).
  record Folder,
    path : Path,
    entry : Path? = nil,
    files = [] of Path,
    app = false,
    core = false

  # Recursively visits directories starting at, and including,
  # *root*, and creates `Folder`s for their corresponding paths
  # in *folders*.
  def load(folders : Hash(Path, Folder), root : Path, app = false, core = false)
    return if folders.has_key?(root)

    if File.file?(entry = root / "#{root.stem}.nk")
      folders[root] = folder = Folder.new(root, entry, app: app, core: core)
    else
      folders[root] = folder = Folder.new(root, app: app, core: core)
    end

    Dir.glob(root / "*.nk") do |path|
      unless (path = Path[path]) == entry
        folder.files << path
      end
    end

    Dir.glob(root / "*/") do |path|
      load(folders, Path[path])
    end
  end

  # Runs the file at *path* using *engine*. A new block is
  # created for *path* as a child of *toplevel*.
  #
  # Words from the new block are imported into *toplevel*
  # after the engine successfully exhausts it.
  #
  # Returns *toplevel*.
  def run(engine : Engine, toplevel : Block, path : Path) : Block
    source = File.read(path)
    block = Block.new(toplevel).slurp(source)
    block.at(Word.new("__path__"), Quote.new(path.parent.to_s))
    block.at(Word.new("__file__"), Quote.new(path.to_s))
    engine.schedule!(block, stack: Block.new)
    engine.exhaust
    toplevel.import!(from: block)
  end

  # Runs *folder*. First, its entry file is run (if any). Then,
  # all other files are run.
  def run(engine : Engine, toplevel : Block, folder : Folder)
    if entry = folder.entry
      run(engine, toplevel, entry)
    end
    run(engine, toplevel, folder.files)
  end

  # Runs an array of *paths* (each is assumed to be a file).
  def run(engine : Engine, toplevel : Block, paths : Array(Path))
    paths.each { |path| run(engine, toplevel, path) }
  end

  # Runs an array of *folders*.
  def run(engine : Engine, toplevel : Block, folders : Array(Folder))
    folders.each { |folder| run(engine, toplevel, folder) }
  end

  # Returns whether the output of Novika should be colorful.
  #
  # Whether this will be respected by general Novika code cannot
  # be guaranteed, but it is guaranteed to be respected by the
  # CLI frontend.
  def colorful? : Bool
    STDOUT.tty? && STDERR.tty? && ENV["TERM"]? != "dumb" && !ENV.has_key?("NO_COLOR")
  end

  # Appends the CLI help message to *io*.
  private def help(io)
    Colorize.enabled = Colorize.enabled?.tap do
      # Contextually enable/disable colors depending on whether
      # the user wants them.
      Colorize.enabled = colorful?

      on = "on by default".colorize.bold

      io << <<-END
      novika - command-line frontend to the Novika programming language [#{VERSION}].

      #{" Syntax              ".colorize.reverse.bold}

        novika [switches] [runnables]

      #{" Switches            ".colorize.reverse.bold}

        -p                    \twrites dense (callers are recorded) profiling data to 'prof.novika.csv'
        -ps                   \twrites sparse profiling data to 'prof.novika.csv'
        -h, --help, h, help, ?\tprints this message

      #{" Runnables           ".colorize.reverse.bold}

      * When #{"runnable".colorize.bold} is a file, it is run.

      * When #{"runnable".colorize.bold} is a directory, *.nk files in it are run. First, <directory-name>.nk
        file is run (if it exists), then, all other files are run. Lastly, this process is
        repeated on sub-directories (if any).

      * When #{"runnable".colorize.bold} is a feature, its words are exposed to all other files and features
        run. Here is a list of available features:

      END

      features = Bundle.features

      features.select(&.on_by_default?).each do |feature|
        io.puts
        io << "    - " << on << " " << feature.id << " (" << feature.purpose << ")"
      end

      features.reject(&.on_by_default?).each do |feature|
        io.puts
        io << "    - " << feature.id << " (" << feature.purpose << ")"
      end

      io.puts

      io << <<-END

      #{" Autoloading         ".colorize.reverse.bold}

      Novika autoloads (implicitly loads) the directory named 'core' in the current
      working directory, and the directory named 'core' in '~/.novika' (assuming they
      exist at their respective locations.)

      #{" Home directory      ".colorize.reverse.bold}

      Novika home directory, '~/.novika', is where globally accessible runnables
      are found. When a runnable cannot be found in the current working directory,
      '~/.novika' is searched.

      #{" Usage examples      ".colorize.reverse.bold}

      $ novika hello repl.nk
               ----- -------
               (1)    (2)

      Here is what it does. First,

      (1) runs the directory called 'hello', found in the working directory or in '~/.novika'; then
      (2) runs the file called 'repl.nk', found in the working directory.

      $ novika console examples/snake.nk
               ------- -----------------
               (1)     (2)

      Here is what it does. First,

      (1) enables the console feature (it's off by default), then
      (2) runs the file called 'snake.nk', found in directory 'examples'.

      If you're having any issues, head out to https://github.com/novika-lang/novika/issues,
      and click "New issue".

      END
    end
  end

  # Writes recent profiling information for *engine* to *filename*
  # using the CSV format.
  private def dump_profile(engine : Engine, filename, small = false)
    result = CSV.build do |csv|
      csv.row "Block ID", "Pseudonym(s)", "Scheduler ID", "Amt of schedules", "Cumulative time (ms)", "Representation"

      engine.prof.each_value do |stat|
        total_count = stat.scheduled_by.each_value.sum(&.count)
        total_cumul = stat.scheduled_by.each_value.compact_map(&.cumul).sum(&.total_milliseconds)
        csv.row stat.id, stat.words.join(' '), "*", total_count, total_cumul, stat.block.to_s
        next if small

        stat.scheduled_by.each do |sched_id, sched|
          csv.row "", "", sched_id, sched.count, sched.cumul.try &.total_milliseconds || "-", ""
        end
      end
    end

    File.write(filename, result)
  end

  # Novika command-line frontend entry point.
  def cli(args : Array(String), cwd = Path[ENV["NOVIKA_PATH"]? || Dir.current])
    if ARGV.any?(/^\-{0,2}(?:h(?:elp)?|\?)$/)
      help(STDOUT)
      exit(0)
    end

    # Files the user specified.
    files = [] of Path
    # Folders the user specified.
    folders = {} of Path => Folder

    # Prefer local home over global home. Global home can
    # only be called '.novika'. Local home may be called
    # either '.novika', or 'env'.
    unless File.directory?(dothome = cwd / ".novika") || File.directory?(dothome = cwd / "env")
      dothome = Path.home / ".novika"
    end

    # Autoload 'core' in '~/.novika', if there is any.
    #
    # Note that '~/.novika' is never an app.
    if File.directory?(dothome / "core")
      load(folders, dothome / "core", core: true)
    end

    # Autoload 'core' in current working directory, if there
    # is any.
    if had_cwd_core = File.directory?(cwd / "core")
      load(folders, cwd / "core", core: true, app: File.file?(cwd / ".nk.app"))
    end

    # If haven't found core in current working directory,
    # then the user is probably looking for help...
    if ARGV.empty? && !had_cwd_core
      help(STDOUT)
      exit(0)
    end

    # Whether to profile at all.
    profile = false
    # Whether to profile sparsely.
    profile_small = false

    bundle = Bundle.new
    toplevel = Block.new(bundle.bb)

    # Populate the bundle with all features. We'll then enable
    # those we want.
    Bundle.features.each { |feature| bundle << feature }

    # Enable on-by-default features.
    bundle.enable_default

    args.each do |arg|
      if bundle.includes?(arg)
        bundle.enable(arg)
        next
      elsif arg.in?("-p", "-profile")
        profile = true
        puts <<-END
          Note: you have enabled profiling. When in profiling mode,
          your programs will run a lot slower, because a lot of data
          is being collected.
        END
        next
      elsif arg == "-ps"
        profile = true
        profile_small = true
        puts <<-END
          Note: you have enabled profiling. When in profiling mode,
          your programs will run a lot slower, because a lot of data
          is being collected.
        END
        next
      end

      # Resolve the path. Prefer current working directory
      # over '~/.novika'.
      if File.exists?(path = Path[arg].expand(cwd))
        # Path exists in current working directory...
      elsif File.exists?(path = dothome / arg)
        # Path exists in '~/.novika'...
      else
        abort "#{arg.colorize.bold} is not a file, directory, or feature avaliable in #{cwd} or ~/.novika"
      end

      if File.directory?(path)
        # Path is a directory: load it.
        load(folders, path, app: File.file?(path / ".nk.app"))
      elsif File.file?(path)
        # Path is a file: add it to files array.
        files << path
      end
    end

    # Get all apps.
    #
    # Note also, that since `folders` is a hash, things like
    # `$ novika new new` will become `$ novika new` and
    # therefore won't participate in the size check below.
    apps = folders.values.select(&.app)

    if apps.size > 1
      # If there is more than one app, and core is one of
      # them, then try to save on it.
      apps.reject!(&.core)

      # ... reflect on folders as well.
      folders.reject! { |k, v| v.app && v.core }
    end

    # If there is more than one app still, abort.
    if apps.size > 1
      abort "cannot run more than one app (namely: #{apps.join(", ", &.path.basename)}); aborting"
    end

    engine = Engine.new(profile)
    run(engine, toplevel, folders.values)
    run(engine, toplevel, files)

    if profile
      puts "Done! Writing profiling results to prof.novika.csv..."
      dump_profile(engine, "prof.novika.csv", small: profile_small)
    end
  rescue e : Error
    e.report(STDERR)
  end
end

{% if flag?(:novika_frontend) %}
  Novika.cli(ARGV)
{% end %}
