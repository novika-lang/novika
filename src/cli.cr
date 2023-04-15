require "./novika"
require "./common"
require "tablo"

module Novika::Frontend::CLI
  extend self

  # A crude sample-based profiler which is triggered on every
  # form the engine tries to execute.
  #
  # Counts the amount of times a form was attempted to be open
  # by the engine.
  #
  # You can use `to_table` to convert a snapshot of data to a
  # `Tablo::Table` table.
  class Profiler
    include IExhaustTracker

    # Represents a profile entry.
    class Profile
      def initialize(@str : String)
        @samples = 0u64
      end

      def <=>(other : Profile)
        @samples <=> other.@samples
      end

      def sample
        @samples += 1
      end

      def ratio(whole : Float64)
        @samples / whole
      end

      def to_row?(nperiods)
        [@str, @samples, @samples/nperiods]
      end
    end

    # Initializes this profiler.
    #
    # *period* is the period between samples, in Engine loop
    # ticks. The less the value, the more samples are taken
    # and the more precise the results are (but the program
    # may run slower).
    def initialize(@period = 32u64)
      @start = 0u64
      @ticks = 0u64
      @profiles = Hash(String, Profile).new { |_, str| Profile.new(str) }
    end

    # Returns a string version of *form* to be the key in the
    # profiles hash.
    private def encode(form : Form)
      "#{form} (#{form.class.typedesc})"
    end

    def on_form_begin(engine : Engine, form : Form)
      unless @ticks - @start >= @period
        @ticks += 1
        return
      end

      key = encode(form)

      profile = @profiles[key]
      profile.sample

      @profiles[key] = profile

      @start = @ticks
      @ticks += 1
    end

    # Assembles and returns the data from this profiler as
    # a `Tablo::Table`.
    #
    # *cutoff* specifies the ratio [0-1] below which profiles
    # should be rejected (i.e., too insignificant).
    def to_table(cutoff = 0.0001)
      nperiods = @ticks / @period

      rows = @profiles.values
        .reject! { |profile| profile.ratio(nperiods) < cutoff }
        .unstable_sort! { |a, b| b <=> a }
        .compact_map &.to_row?(nperiods)

      rows << ["(coverage: ticks, sampled-ticks%)", @ticks, nperiods / @ticks]

      Tablo::Table.new(rows) do |table|
        table.add_column("Form (typedesc)") { |row| row[0] }
        table.add_column("No. of samples") { |row| row[1] }
        table.add_column("Of all samples, %") { |row| "#{(row[2].as(Float64) * 100).round(4)}%" }
        table.shrinkwrap!(128)
      end
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

  # Runs each of the *paths* (each is assumed to be a file).
  def run(engine : Engine, toplevel : Block, paths : Set(Path))
    paths.each { |path| run(engine, toplevel, path) }
  end

  # Runs each of the *folders*.
  def run(engine : Engine, toplevel : Block, folders : Set(Folder))
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
      novika - command-line frontend for Novika #{VERSION}

      Syntax:

        novika [switches] [runnables]

      Switches:

        -h, --help, h, help, ?  prints this message
        -p[:PERIOD]             enables profiling, samples every PERIOD ticks (default: 16)

      Runnables:

        #{"file".colorize.bold}

          When runnable is a file, that file is read and run.

          Examples:

            $ novika hello.nk
            $ novika a.nk b.nk c.nk
            # Note: order matters. That is, a.nk <- b.nk <- c.nk,
            # where '<-' means "is executed before & visible to"

        #{"library directory".colorize.bold}

          Any directory is implicitly a library directory. A directory may be
          explicitly marked as a library directory by putting a .nk.lib manifest
          file inside it.

          When runnable is a library directory, *.nk files in it are run. First,
          <directory-name>.nk file is run (if it exists), then, all other files are
          run. Lastly, this process is repeated on sub-directories (if any).

          Examples:

            $ mkdir foo
            $ echo "'Hi from lib core!' echo" > foo/foo.nk
            $ echo "'Salutations from lib slave!' echo" > foo/slave.nk
            $ novika foo
            Hi from lib core!
            Salutations from lib slave!

        #{"application directory".colorize.bold}

          Mostly similar to library directories. Marked by .nk.app manifest file
          inside the directory. Note that:

          * For appplication directories, <directory-name>.nk file is run last
            rather than first.

          * You cannot provide more than one application directory.

          Examples:

            $ mkdir bar
            $ touch bar/.nk.app
            $ echo "'Hi from app core!' echo" > bar/bar.nk
            $ echo "'Salutations from app slave!' echo" > bar/slave.nk
            $ novika bar
            Salutations from app slave!
            Hi from app core!

        #{"capability id".colorize.bold}

          When runnable is a capability id, the corresponding capability is enabled
          to all other files and capabilities run (that is, everyone is allowed to
          use it).

          A runnable might ask you for permission to enable a capability or two
          (for example, disk and/or ffi). Your choice to allow is remembered;
          your choice to deny isn't.

          Here is a list of available capabilities:

      END

      available_caps = CapabilityCollection.available

      available_caps.select(&.on_by_default?).each do |cap|
        io.puts
        io << "      - " << on << " " << cap.id << " (" << cap.purpose << ")"
      end

      available_caps.reject(&.on_by_default?).each do |cap|
        io.puts
        io << "      - " << cap.id << " (" << cap.purpose << ")"
      end

      io.puts

      io << <<-END

      Autoloading:

        Novika autoloads (implicitly loads) the directory named 'core' in the
        current working directory, and the directory named 'core' in '~/.novika'
        (assuming they exist at their respective locations.)

      Home directory:

        Novika home directory, '~/.novika', is where globally accessible runnables
        are found. When a runnable cannot be found in the current working directory,
        '~/.novika' is searched.

      Examples:

        Run the Novika REPL:
          $ novika repl

        Run the REPL, but preload a file first:
          $ novika foo.nk repl

        Create a Novika app (you must be inside an empty directory)
          $ novika new

        Run the snake example:
          $ novika console examples/snake.new.nk

      Something doesn't seem to work right?

        Feel free to file an issue at https://github.com/novika-lang/novika/issues/new.

      END
    end
  end

  # Novika command-line frontend entry point.
  def start(args = ARGV, cwd = Path[ENV["NOVIKA_PATH"]? || Dir.current])
    if args.any?(/^\-{0,2}(?:h(?:elp)?|\?)$/)
      help(STDOUT)
      exit(0)
    end

    profiler = nil

    args.reject! do |arg|
      if status = arg =~ /^\-p(?::([1-9]\d*))?$/
        profiler = Profiler.new($~[1]?.try(&.to_u64) || 16u64)
      end
      status
    end

    profiler.try { |it| Engine.trackers << it }

    # Populate the capability collection with all available
    # capabilities. Only enable default ones.
    #
    # We'll then enable those that the user wants.
    caps = CapabilityCollection.with_available
    caps.enable_default

    resolver = RunnableResolver.new(args, caps, cwd)
    unless resolver.resolve?
      help(STDOUT)
      exit(0)
    end

    # If more than one app, try to reject core (it is assumed
    # to be picked up implicitly; the "cost" of ignoring it is
    # less than that of an explicitly specified app).
    if resolver.apps.size > 1
      resolver.apps.reject! do |app|
        next if !app.core? || app.explicit?

        # Also reject capabilities that the app requested!
        resolver.capabilities.reject! do |cap|
          next if cap.manual?

          cap.root == app.path
        end

        true
      end
    end

    # If still more than one, then we don't know what to do
    # with them.
    if resolver.apps.size > 1
      Frontend.errln("cannot determine which app to run (given apps: #{resolver.apps.join(", ", &.path.basename)})")
      exit(1)
    end

    # Found a bunch of unknown... things. We don't know what
    # to do with them either.
    #
    # TODO: this takes into account things from .nk.app and .nk.lib
    # files, which makes everything a bit confusing.
    unless resolver.unknowns.empty?
      resolver.unknowns.each do |arg|
        Frontend.errln(
          "could not resolve runnable #{arg.colorize.bold}: it's not a file, \
           directory, shared object, Novika app, or capability id")
      end
      exit(1)
    end

    # Create a library for each shared object, and put it in
    # the capability collection.
    #
    # For each shared object, a library ID is made by taking the stem
    # of path to the object and stripping it of the lib prefix, if it
    # has one. For example, given `/lib/libmath.so` or `/lib/math.so`,
    # the library ID would be `math` in both cases.
    #
    # Err if a library with the same id exists already.
    resolver.shared_objects.each do |shared_object|
      id = shared_object.stem.lchop("lib")

      if caps.has_library?(id)
        Frontend.errln("multiple libraries with the same id: #{id}")
        exit(1)
      end

      caps << Library.new(id, shared_object)
    end

    caps.on_load_library? do |id|
      Library.new?(id, resolver)
    end

    Engine.new(caps) do |engine|
      # Important: wrap capability block in another block! This is
      # required to make it possible to ignore capability block in
      # Image emission, saving some time and space!
      toplevel = Block.new(caps.block)

      resolver.capabilities.each do |req|
        allowed =
          req.allowed? do
            # If we've got it here, then it's in the capability
            # collection, therefore, the capability class exists.
            purpose = caps.get_capability_class?(req.id).not_nil!.purpose

            print "[novika] Permit '#{req.root.basename}' to use #{req.id} (#{purpose})? [Y/n] "
            (gets.try &.downcase) == "y"
          end

        caps.enable(req.id) if allowed
      end

      run(engine, toplevel, resolver.folders)
      run(engine, toplevel, resolver.files)
      run(engine, toplevel, resolver.apps)
    ensure
      profiler.try { |it| puts it.to_table }
    end
  rescue e : Error
    e.report(STDERR)
    exit(1)
  end
end

Novika::Frontend::CLI.start
