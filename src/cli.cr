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

  # Appends the CLI help message to *io*.
  private def help(io)
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

  # Novika command-line frontend entry point.
  def start(args = ARGV, cwd = Path[ENV["NOVIKA_CWD"]? || Dir.current])
    Colorize.enabled = Novika.colorful?

    if args.any?(/^\-{1,2}:?(?:h(?:elp)?|\?)$/)
      help(STDOUT)
      exit(0)
    end

    profiler = nil
    dry = false
    help_mode = false
    abort_on_permission_request = false

    args.reject! do |arg|
      case arg
      when /^\-:profile(?::([1-9]\d*))?$/
        profiler = Profiler.new($~[1]?.try(&.to_u64) || 16u64)
      when /^\-:dry$/
        dry = true
      when /^\-:abort-on-permission-request$/
        abort_on_permission_request = true
      when /^help$/
        help_mode = true
      else
        next false
      end

      true
    end

    profiler.try { |prof| Engine.trackers << prof }

    resolver = RunnableResolver.new(cwd, args.map { |arg| Resolver::RunnableQuery.new(arg) })

    # Autoload env and cwd. We don't really care whether env autoloading
    # has succeeded. On the other hand, if cwd autoloading hasn't, we
    # have an opportunity to load the default runnable, or show help
    # if the latter doesn't exist.
    cwd_set, cwd_q = resolver.autoload_cwd?

    resolver.rejected.reject!(cwd_q) if cwd_q

    if args.empty? && resolver.rejected.empty? && (cwd_set.nil? || cwd_set.lib?)
      unless resolver.from_query?("__default__")
        help(STDOUT)
        exit(0)
      end
    end

    # Try to process the arguments.
    resolver.from_queries(args)
    resolver.preload!

    # If there are any unresolved runnables, print them and their
    # backtraces and quit. This is an error.
    unless resolver.rejected.empty?
      resolver.rejected.each do |runnable|
        runnable.backtrace(STDERR, indent: 2) do |io|
          Frontend.err("could not resolve runnable: #{runnable}", io)
        end
      end

      exit(1)
    end

    # Then, if there are any ignored runnables, print them as
    # well but do not quit.
    resolver.ignored.each do |runnable|
      runnable.backtrace(STDERR, indent: 2) do |io|
        Frontend.note("the following runnable is not allowed here: #{runnable}", io)
      end
    end

    unless help_mode
      # Collect apps for further analysis.
      apps = Set(Resolver::RunnableGroup).new
      resolver.accepted.each do |set|
        set.each_unique_app { |app| apps << app }
      end

      if apps.size > 1
        apps.each do |app|
          app.backtrace(STDERR, indent: 2) do |io|
            Frontend.note("cannot run #{app} because it's not the only one\n", io)
          end
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
    end

    # Form one big ResolutionSet from all ResolutionSets we are going
    # to run. This takes care of any repetitions, in dependencies, as
    # well as in resolutions themselves.
    program = Resolver::ResolutionSet.new

    if help_mode
      first = true

      resolver.accepted.each do |set|
        program.append(set)
      end

      program.each_preamble_with_group(resolver.@root) do |preamble, group|
        # ↓ Is there a more elegant way?
        #
        # TODO: test that preambles aren't "inherited"
        ancestor_queries = group.ancestors.select(Resolver::RunnableQuery)
        next if ancestor_queries.empty?
        next unless ancestor_queries.any? { |query| args.any? { |arg| query == arg } }

        if first
          first = false
        else
          print "\n\n"
        end
        puts preamble
      end

      if first
        help(STDOUT)
      end

      exit(0)
    end

    resolver.preloaded.each do |set|
      program.append(set)
    end

    program.append(cwd_set) if cwd_set

    resolver.accepted.each do |set|
      program.append(set)
    end

    if dry
      puts <<-HINT
      --> Showing environment designations (which environment is going to run which file).
      --> Order matters, and is exactly the execution order.
      HINT

      puts

      program.each_designation(resolver.@root) do |designation|
        puts designation
      end

      exit(0)
    end

    resolver.@root.send(Resolver::DoDiskLoad.new)
    resolver.@root.send(Resolver::ToAskDo.new do |question|
      if abort_on_permission_request
        abort
      end

      print question, " "
      gets
    end)

    resolver.@root.send(Resolver::ToAnswerDo.new do |answer|
      print answer
    end)

    # Enable dependencies required by these resolution sets.
    #
    # Currently we do it in a way that completely throws away any
    # actual usefulness/safety guarantees the dependency system
    # may have provided. There are reasons but hopefully this
    # isn't going to be the case in the future.
    program.each_unique_dependency_with_dependents do |dependency, dependents|
      skiplist = Set(Resolver::Resolution).new
      visited = Set(Resolver::RunnableGroup).new

      # Go through apps and libs, add their resolutions to the skiplist.
      # React only to never-seen-before groups.
      dependents.each_group do |group, resolution|
        next unless group.app? || group.lib?

        if group.in?(visited)
          skiplist << resolution
          next
        end

        # Find container that maps to the group/lib
        container = resolver.@root.containerof(group)
        container.request(dependency)

        visited << group
        skiplist << resolution
      end

      # For all resultions not belonging to an app or lib, simply
      # allow the use of the dependency.
      #
      # `request` isn't expected to be called recursively, therefore,
      # we only allow dependencies from `explicit?` queries -- the same
      # thing we'd do with some other more "elegant" way.
      dependents.each do |resolution|
        next if resolution.in?(skiplist)

        resolution.each_dependency(&.allow)
      end
    end

    resolver.@root.send(Resolver::DoDiskSave.new)

    begin
      program.each_designation(resolver.@root, &.run)
    ensure
      profiler.try { |prof| puts prof.to_table }
    end
  rescue e : Resolver::ResolverError
    if runnable = e.runnable?
      runnable.backtrace(STDERR, indent: 2) do |io|
        Frontend.err(e.message, io)
      end
    else
      Frontend.errln(e.message)
    end
    exit(1)
  rescue e : Error
    e.report(STDERR)
    exit(1)
  end
end

Novika::Frontend::CLI.start
