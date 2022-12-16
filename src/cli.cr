require "./novika"
require "./common"

module Novika::Frontend::CLI
  extend self

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

  # Appends the CLI help message to *io*.
  private def help(io)
    Colorize.enabled = Colorize.enabled?.tap do
      # Contextually enable/disable colors depending on whether
      # the user wants them.
      Colorize.enabled = Novika.colorful?

      on = "on by default".colorize.bold

      io << <<-END
      novika - command-line frontend to the Novika programming language [#{VERSION}].

      #{" Syntax              ".colorize.reverse.bold}

        novika [switches] [runnables]

      #{" Switches            ".colorize.reverse.bold}

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

  # Novika command-line frontend entry point.
  def start(args = ARGV, cwd = Path[ENV["NOVIKA_PATH"]? || Dir.current])
    if args.any?(/^\-{0,2}(?:h(?:elp)?|\?)$/)
      help(STDOUT)
      exit(0)
    end

    # Populate the bundle with all features. Only enable
    # default ones. We'll then enable those that the user
    # wants.
    bundle = Bundle.with_all
    bundle.enable_default

    resolver = RunnableResolver.new(args, bundle, cwd)
    unless resolver.resolve?
      help(STDOUT)
      exit(0)
    end

    # If more than one app, try to reject core (it is assumed
    # to be picked up implicitly; the price of ignoring it is
    # less than that of an explicitly specified app).
    if resolver.apps.size > 1
      resolver.apps.reject! { |app| app.core }
    end

    # If still more than one, then we don't know what to do
    # with them.
    if resolver.apps.size > 1
      Frontend.errln("cannot determine which app to run (given apps: #{resolver.apps.join(", ", &.path.basename)})")
      exit(1)
    end

    # Found a bunch of unknown... things. We don't know what
    # to do with them either.
    unless resolver.unknowns.empty?
      resolver.unknowns.each do |arg|
        Frontend.errln("could not resolve runnable #{arg.colorize.bold}: it's not a file, directory, app, or feature")
      end
      exit(1)
    end

    engine = Engine.new(bundle) do |engine|
      # Important: wrap bundle block in another block! This is
      # required to make it possible to ignore bundle block in
      # Image emission, saving some time and space!
      toplevel = Block.new(bundle.bb)

      resolver.features.each { |feature_id| bundle.enable(feature_id) }
      resolver.folders.each { |folder| run(engine, toplevel, folder) }
      resolver.files.each { |file| run(engine, toplevel, file) }
      resolver.apps.each { |app| run(engine, toplevel, app) }
    end
  rescue e : Error
    e.report(STDERR)
    exit(1)
  end
end

Novika::Frontend::CLI.start
