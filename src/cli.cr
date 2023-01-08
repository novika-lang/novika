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

  # Runs the given *folder*.
  #
  # If *folder* is an app, all other files in it (if any) are
  # run first, then its entry file (again, only if it exists).
  #
  # If *folder* is a lib, its entry file is run first (if it
  # exists), followed by all other files.
  #
  # The "philosophy" is as follows:
  #
  # * For apps, it's all other files contributing to the entry
  #   file, which generally contains run instructions.
  #
  # * For libs, it's the lib's entry file contributing to all
  #   other files -- allowing to share code in load order-
  #   agnostic way.
  def run(engine : Engine, toplevel : Block, folder : Folder)
    run(engine, toplevel, folder.files) if folder.app?

    if entry = folder.entry?
      run(engine, toplevel, entry)
    end

    run(engine, toplevel, folder.files) unless folder.app?
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
      resolver.apps.reject!(&.core?)
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
        Frontend.errln(
          "could not resolve runnable #{arg.colorize.bold}: it's not a file, \
           directory, shared object, Novika app, or feature ID")
      end
      exit(1)
    end

    # Create a library for each shared object, and put it in
    # the bundle.
    #
    # For each shared object, a library ID is made by taking the stem
    # of path to the object and stripping it of the lib prefix, if it
    # has one. For example, given `/lib/libmath.so` or `/lib/math.so`,
    # the library ID would be `math` in both cases.
    #
    # Err if a library with the same id exists already.
    resolver.shared_objects.each do |shared_object|
      id = shared_object.stem.lstrip("lib")

      if bundle.has_library?(id)
        Frontend.errln("multiple libraries with the same id: #{id}")
        exit(1)
      end

      bundle << Library.new(id, shared_object)
    end

    bundle.on_load_library? do |id|
      Library.new?(id, resolver)
    end

    Engine.new(bundle) do |engine|
      # Important: wrap bundle block in another block! This is
      # required to make it possible to ignore bundle block in
      # Image emission, saving some time and space!
      toplevel = Block.new(bundle.bb)

      resolver.features.each { |feature_id| bundle.enable(feature_id) }
      run(engine, toplevel, resolver.folders)
      run(engine, toplevel, resolver.files)
      run(engine, toplevel, resolver.apps)
    end
  rescue e : Error
    e.report(STDERR)
    exit(1)
  end
end

Novika::Frontend::CLI.start
