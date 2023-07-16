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
    dump_tree = false
    help_mode = false
    abort_on_permission_request = false

    args.reject! do |arg|
      case arg
      when /^\-:profile(?::([1-9]\d*))?$/
        profiler = Profiler.new($~[1]?.try(&.to_u64) || 16u64)
      when /^\-:dry$/
        dry = true
      when /^\-:dump-resolver-tree$/
        dump_tree = true
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

    resolver = RunnableResolver.new(cwd, args)

    resolver.on_permissions_gets do |string|
      if abort_on_permission_request
        abort
      end

      print string, " "
      gets
    end

    resolver.on_permissions_print do |string|
      print string
    end

    resolver.after_container_rewritten do |container|
      next unless dump_tree

      puts container
    end

    resolver.after_response do |hook|
      if dump_tree
        exit(0)
      end

      # Having some runnables ignored isn't an error, but we should
      # still notify the user so that they know something is wrong.
      hook.response.each_ignored_runnable do |runnable|
        runnable.backtrace(STDERR, indent: 2) do |io|
          Frontend.note("this runnable is not allowed here, and will be ignored: #{runnable}", io)
        end
      end

      next unless help_mode

      first = true

      hook.each_queried_for_preamble_with_group do |preamble, group|
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

    resolver.after_program do |hook|
      next unless dry

      puts <<-HINT
      --> Showing environment designations (which environment is going to run which file).
      --> Order matters, and is exactly the execution order.
      HINT

      puts

      hook.each_designation do |designation|
        puts designation
      end

      exit(0)
    end

    resolver.after_permissions do |hook|
      hook.run
    ensure
      profiler.try { |prof| puts prof.to_table }
    end

    unless resolver.resolve?
      help(STDOUT)
      exit(0)
    end
  rescue e : Resolver::RunnableError
    e.runnable.backtrace(STDERR, indent: 2) do |io|
      Frontend.err(e.message, io)
    end
    exit(1)
  rescue e : Resolver::ResponseRejectedError
    e.response.each_rejected_runnable do |runnable|
      runnable.backtrace(STDERR, indent: 2) do |io|
        Frontend.err(e.message, io)
      end
    end
    exit(1)
  rescue e : Resolver::MoreThanOneAppError
    e.apps.each do |app|
      app.backtrace(STDERR, indent: 2) do |io|
        Frontend.noteln("could not run this app because it's not the only one", io)
      end
    end

    Frontend.errln(e.message)
    exit(1)
  rescue e : Resolver::ResolverError
    Frontend.errln(e.message)
  rescue e : Error
    e.report(STDERR)
    exit(1)
  end
end

Novika::Frontend::CLI.start
