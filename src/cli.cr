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
        [@str, @samples]
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
      String.build do |io|
        form.spot(io, vicinity: 16, colorful: false)

        io << " (" << form.class.typedesc << ")"
      end
    end

    def on_form_begin(engine : Engine, form : Form)
      unless @ticks - @start >= @period
        @ticks += 1
        return
      end

      # Capture blocks of the continuations stack.
      engine.each_active_block do |block|
        profile = @profiles[repr = encode(block)]
        profile.sample
        @profiles[repr] = profile
      end

      @start = @ticks
      @ticks += 1
    end

    # Assembles and returns the data from this profiler as
    # a `Tablo::Table`.
    #
    # *cutoff* specifies the ratio [0-1] below which profiles
    # should be rejected (i.e., too insignificant).
    def to_table(cutoff = 0.01)
      nperiods = @ticks / @period

      rows = @profiles.values
        .reject! { |profile| profile.ratio(nperiods) < cutoff }
        .unstable_sort! { |a, b| b <=> a }
        .compact_map &.to_row?(nperiods)

      rows << ["(coverage: ticks)", @ticks]

      Tablo::Table.new(rows) do |table|
        table.add_column("Form (typedesc)") { |row| row[0] }
        table.add_column("No. of samples") { |row| row[1] }
        table.shrinkwrap!(128)
      end
    end
  end

  private def print_traceback(io : IO, focus : Resolver::Runnable, resolver : RunnableResolver)
    traceback = [focus] of Resolver::Runnable::Ancestor
    focus.each_ancestor do |ancestor|
      traceback.unshift(ancestor)
    end

    traceback.each do |runnable|
      io << "  ╿ in "
      if runnable.is_a?(Resolver::RunnableContainer)
        runnable.to_s(io, lead: 0, indent: 4)
      else
        io << runnable << '\n'
      end
    end
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
      case arg
      when /^\-p(?::([1-9]\d*))?$/
        profiler = Profiler.new($~[1]?.try(&.to_u64) || 16u64)
      else
        next false
      end

      true
    end

    profiler.try { |prof| Engine.trackers << prof }

    caps = CapabilityCollection.with_available.enable_default
    resolver = RunnableResolver.new(caps, cwd)

    caps.on_load_library? do |name|
      Library.new?(name, resolver)
    end

    begin
      # Autoload env and cwd. We don't really care whether env autoloading
      # had succeeded. On the other hand, if cwd autoloading hadn't, we
      # have an opportunity to show help.
      env_set, env_q = resolver.autoload_env?
      cwd_set, cwd_q = resolver.autoload_cwd?

      resolver.rejected.reject!(env_q) if env_q
      resolver.rejected.reject!(cwd_q) if cwd_q

      if ARGV.empty? && resolver.rejected.empty? && (cwd_set.nil? || cwd_set.lib?)
        help(STDOUT)
        exit(0)
      end

      # Now that autoloading is done, try to process the arguments.
      explicits = resolver.from_queries(args)
    rescue e : Resolver::ResolverError
      print_traceback(STDERR, e.runnable, resolver)
      Frontend.errln(e.message)
      exit(1)
    end

    # If there are any unresolved runnables, print them and their
    # backtraces and quit. This is an error.
    unless resolver.rejected.empty?
      resolver.rejected.each do |runnable|
        print_traceback(STDERR, runnable, resolver)
        Frontend.errln("could not resolve runnable: #{runnable}")
      end

      exit(1)
    end

    # Then, if there are any ignored runnables, print them as
    # well but do not quit.
    resolver.ignored.each do |runnable|
      print_traceback(STDERR, runnable, resolver)
      Frontend.noteln("the following runnable is not allowed here: #{runnable}", io: STDERR)
    end

    # Collect apps for further analysis.
    apps = Set(Resolver::RunnableGroup).new
    resolver.accepted.each do |set|
      apps.concat(set.unique_apps)
    end

    if apps.size > 1
      apps.each do |app|
        print_traceback(STDERR, app, resolver)
        Frontend.noteln("cannot run #{app} because it's not the only one\n", io: STDERR)
      end

      Frontend.errln("cannot determine which one of the above apps to run")

      exit(1)
    end

    # If one app was accepted and cwd is also an app, reject cwd
    # because it is implicitly loaded (i.e. prefer explicit
    # app over magic).
    if cwd_set && cwd_set.app? && (apps.size == 1 || !args.empty?)
      cwd_set = nil
    end

    # Form one big ResolutionSet from all ResolutionSets we are going
    #  to run. This take scare of any repetitions, in dependencies, as
    # well as in resolutions themselves.
    program = Resolver::ResolutionSet.new
    program.append(env_set) if env_set
    program.append(cwd_set) if cwd_set

    resolver.accepted.each do |set|
      program.append(set)
    end

    permissions = PermissionServer.new(caps, resolver, explicits)
    permissions.load

    # Enable dependencies required by these resolution sets.
    #
    # Currently we do it in a way that completely throws away any
    # actual usefulness/safety guarantees the dependency system
    # may have provided. There are reasons but hopefully this
    # isn't going to be the case in the future.
    program.each_unique_dependency_with_dependents do |dependency, dependents|
      permissions.request(dependency, for: dependents)

      dependency.enable(in: caps)
    end

    permissions.save

    # Important: wrap capability block in another block! This is
    # required to make it possible to ignore capability block in
    # Image emission, saving some time and space!
    toplevel = Block.new(caps.block)
    toplevel.at(Word.new("__runtime__"), Quote.new("novika"))

    engine = Engine.push(caps)

    begin
      program.each do |resolution|
        resolution.run(engine, toplevel)
      end
    ensure
      profiler.try { |prof| puts prof.to_table }
    end
  rescue e : Error
    e.report(STDERR)
    exit(1)
  end
end

Novika::Frontend::CLI.start
