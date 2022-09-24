require "big"
require "csv"
require "colorize"
require "file_utils"

# Order is important!
require "./novika/forms/form"
require "./novika/errors"
require "./novika/tape"
require "./novika/table"
require "./novika/forms/*"
require "./novika/engine"
require "./novika/feature"
require "./novika/features/*"
require "./novika/features/impl/*"

module Novika
  extend self

  VERSION = "0.0.2"

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
      Colorize.enabled = colorful?

      on = "on by default".colorize.bold

      io << <<-END
      novika - command-line frontend to the Novika programming language [#{VERSION}].

      #{" Syntax              ".colorize.reverse.bold}

        novika [switches] [runnables]

      #{" Switches            ".colorize.reverse.bold}

        -p        \twrites dense (callers are recorded) profiling data to 'prof.novika.csv'
        -ps       \twrites sparse profiling data to 'prof.novika.csv'
        -h, --help\tprints this message

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
      almost always use the following command:

        $ novika core path/to/the/file/you/want/to/run.nk

      #{" Examples            ".colorize.reverse.bold}

      $ novika core repl.nk
               ---- -------
               std  file

      $ novika core console examples/snake.nk
               ---- ------- -----------------
               std  feature file

      If you're having any issues, head out to https://github.com/novika-lang/novika/issues,
      and click "New issue".

      END
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
    if ARGV.empty? || ARGV.any?(/^\-{0,2}(?:h(?:elp)?|\?)$/)
      help(STDERR)
      exit(1)
    end

    bundle = Bundle.new
    Bundle.features.each { |feature| bundle << feature }

    bundle.enable_default

    files = [] of Path
    folders = {} of Path => Folder

    profile = false
    profile_small = false

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

    if profile
      puts "Done! Writing profiling results to prof.novika.csv..."

      # Print profiling info if profiling was enabled.
      result = CSV.build do |csv|
        csv.row "Block ID", "Pseudonym(s)", "Scheduler ID", "Amt of schedules", "Cumulative time (ms)", "Representation"

        engine.prof.each_value do |stat|
          total_count = stat.scheduled_by.each_value.sum(&.count)
          total_cumul = stat.scheduled_by.each_value.compact_map(&.cumul).sum(&.total_milliseconds)
          csv.row stat.id, stat.words.join(' '), "*", total_count, total_cumul, stat.block.to_s
          next if profile_small

          stat.scheduled_by.each do |sched_id, sched|
            csv.row "", "", sched_id, sched.count, sched.cumul.try &.total_milliseconds || "-", ""
          end
        end
      end

      File.write("prof.novika.csv", result)
    end
  rescue e : EngineFailure
    e.report(STDERR)
  end
end

{% if flag?(:novika_frontend) %}
  Novika.frontend(ARGV)
{% end %}
