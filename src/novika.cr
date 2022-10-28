require "big"
require "csv"
require "colorize"
require "file_utils"

# Order is important!
require "./novika/forms/form"
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

  VERSION = "0.0.4"

  # Represents a folder with Novika files, containing an `entry`
  # file path (if any; e.g., `core.nk` inside a folder named
  # `core`), and paths for all other `files` (if any).
  record Folder, entry : Path? = nil, files = [] of Path

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

    Dir.glob(root / "*/") do |path|
      collect(folders, Path[path])
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

      #{" Standard library    ".colorize.reverse.bold}

      Most Novika code depends on 'core', which is the language's standard library, so you'd
      almost always use the following command (assuming 'core' exists in your working directory):

        $ novika core path/to/the/file/you/want/to/run.nk

      #{" Usage examples      ".colorize.reverse.bold}

      $ novika core repl.nk
               ---- -------
               (1)    (2)

      Here is what it does. First,

      (1) enables the standard library, then
      (2) runs the file called 'repl.nk', found in the working directory.

      $ novika core console examples/snake.nk
               ---- ------- -----------------
               (1)    (2)         (3)

      Here is what it does. First,

      (1) enables the standard library, then
      (2) enables the console feature (it's off by default), then
      (3) runs the file called 'snake.nk', found in directory 'examples'.

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
  def cli(args : Array(String), cwd = Path[FileUtils.pwd])
    if ARGV.empty? || ARGV.any?(/^\-{0,2}(?:h(?:elp)?|\?)$/)
      help(STDOUT)
      exit(0)
    end

    # Files the user specified.
    files = [] of Path
    # Folders the user specified.
    folders = {} of Path => Folder

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
      elsif File.directory?(arg)
        # Exists and is a directory.
        collect(folders, Path[arg])
      elsif File.file?(arg)
        # Exists and is a file.
        files << Path[arg]
      elsif arg.in?("-p", "-profile")
        profile = true
        puts <<-END
          Note: you have enabled profiling. When in profiling mode,
          your programs will run a lot slower, because a lot of data
          is being collected.
        END
      elsif arg == "-ps"
        profile = true
        profile_small = true
        puts <<-END
          Note: you have enabled profiling. When in profiling mode,
          your programs will run a lot slower, because a lot of data
          is being collected.
        END
      else
        abort "#{arg.colorize.bold} is not a file, directory, or feature avaliable in #{cwd}"
      end
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
