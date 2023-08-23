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

      #{"Syntax".colorize.underline}

        novika [switches] [queries]

      #{"Switches".colorize.underline}

        -h, --help, -?

          Prints this message.

        -:profile[:PERIOD=16]

          Enables profiling, samples every PERIOD ticks, prints sample
          table when all queries exit.

        -:dry-list

          Prints a list of what needs to run in order to satisfy the queries
          and in what order. Use this if you don't understand what's going
          on with run order etc.

          +:dry-list-sm

            Enables environment-relative, uncluttered (#{"sm".colorize.underline}all) mode for
            dry list.

            #{"$ novika -:dry-list +:dry-list-sm repl".colorize.bold}
            # #{"…".colorize.dark_gray}

        -:dry-tree

          Prints a tree of what needs to run in order to satisfy the queries;
          entries in the tree, notably script entries, have backtrace. Use
          this if -:dry-list doesn't help.

        -:abort-on-permission-request

          exit(1) on a request to give permission for the use of a language
          capability or a shared library.

      #{"Help mode".colorize.underline}

        Running `$ novika help [queries]` will print help for each of the
        queries if possible. Note that you cannot #{"run".colorize.bright} anything in help mode.

          #{"$ novika help repl".colorize.bold}
          novika repl - read-eval-print loop for Novika …

          #{"$ novika create repl help".colorize.bold}
          novika create - a tool for scaffolding Novika applications and libraries …
          novika repl - read-eval-print loop for Novika …

      #{"Queries".colorize.underline}

        You run Novika scripts, directories, libraries and apps by
        #{"querying".colorize.bright} Novika.

        #{"script".colorize.bold}

          If you want to run a script, you should pass the path to that
          script (absolute or relative) as a query.

            #{"$ novika hello.nk".colorize.bold}
            #{"$ novika a.nk b.nk c.nk".colorize.bold}
            #{"# Note: order matters. That is, a.nk <- b.nk <- c.nk,".colorize.dark_gray}
            #{"# where '<-' means 'is run before & visible to'".colorize.dark_gray}

        #{"directory".colorize.bold}

          If you want to run a directory that contains some Novika files,
          you should pass the path to that directory (absolute or relative)
          as a query. Load order is as follows:

            1. Subdirectory named 'core/', recursively.
            2. File with the same name as the directory, e.g. for 'foo/'
               it is going to be 'foo/foo.nk'; known as the entry file.
            3. All other files, in lexicographic order.
            4. All other subdirectories, recursively.

          App and lib subdirectories are ignored. Files and directories
          prefixed with one or more `_`s are ignored.

            #{"$ ls foo".colorize.bold}
            a.nk b.nk c.nk foo.nk
            #{"$ novika foo".colorize.bold}
            #{"# Runs foo.nk".colorize.dark_gray}
            #{"# Runs a.nk".colorize.dark_gray}
            #{"# Runs b.nk".colorize.dark_gray}
            #{"# Runs c.nk".colorize.dark_gray}
            #{"$ ls bar".colorize.bold}
            abc/ xyz/ _def/ m.nk n.nk _temp.nk
            #{"$ ls bar/abc".colorize.bold}
            a.nk b.nk c.nk
            #{"$ ls bar/xyz".colorize.bold}
            x.nk y.nk z.nk
            #{"$ novika bar".colorize.bold}
            #{"# Runs m.nk".colorize.dark_gray}
            #{"# Runs n.nk".colorize.dark_gray}
            #{"# Runs abc/a.nk".colorize.dark_gray}
            #{"# Runs abc/b.nk".colorize.dark_gray}
            #{"# Runs abc/c.nk".colorize.dark_gray}
            #{"# Runs xyz/x.nk".colorize.dark_gray}
            #{"# Runs xyz/y.nk".colorize.dark_gray}
            #{"# Runs xyz/z.nk".colorize.dark_gray}

        #{"app".colorize.bold}

          Identified by `.nk.app` manifest. App directories are similar
          in behavior to simple directories, except that (a) the order in
          which their content is visited & run can be determined by their
          manifest, and (b) their entry file is run last rather than first,
          that is, after the subdirectories step. Only one app be queried
          for. Trying to query for more than one app is an error.

            #{"$ mkdir foo".colorize.bold}
            #{"$ cd foo".colorize.bold}
            #{"$ novika create/app".colorize.bold}
            #{"$ ls".colorize.bold}
            core/ .nk.app
            #{"# Note how Novika runs the current working directory here.".colorize.dark_gray}
            #{"# It does that if it can, and if you don't ask it for".colorize.dark_gray}
            #{"# something else.".colorize.dark_gray}
            #{"$ novika".colorize.bold}
            Hello World

        #{"lib".colorize.bold}

          Identified by `.nk.lib` manifest. Lib directories are similar to
          apps. One difference is that several libs can be queried for
          simultaneously. Another is that a library's entry file is run
          first rather than last, that is, after the 'core/' step, the same
          as with simple directories.

            #{"$ mkdir foo bar".colorize.bold}
            #{"$ touch foo/.nk.lib bar/.nk.lib".colorize.bold}
            #{"$ echo '100 $: x' > foo/foo.nk".colorize.bold}
            #{"$ echo '200 $: y' > bar/bar.nk".colorize.bold}
            #{"$ novika foo bar repl".colorize.bold}
            >>> x
            [ 100 ]
            >>> y
            [ 100 200 ]

        #{"manifest".colorize.bold}

          App `.nk.app` and lib `.nk.lib` manifests allow you to control
          which files, directories, and libs are queried for when you run
          the app/lib, and in what order, without needing to specify all
          that via the arguments. App and lib manifests share syntax.

          ╭───────────────────────────────────────────────────────────────────╮
          │ foo/.nk.lib                                                       │
          ├───────────────────────────────────────────────────────────────────╯
          │ #{"# This is a comment. Only full-line comments are supported, like".colorize.dark_gray}
          │ #{"# this one for instance.".colorize.dark_gray}
          │ ffi disk sdl
          │ #{"# Preprocessor expressions are written in brackets [].".colorize.dark_gray}
          │ /path/to/lib.[windows, darwin, ... | dll, dylib, so]
          │ /path/to/file.nk
          │ enter.nk
          │ #{"# '*' means all files in manifest's directory (foo/) except".colorize.dark_gray}
          │ #{"# those that were mentioned before/after.".colorize.dark_gray}
          │ *
          │ nest.nk
          │ xyz/a.nk
          │ #{"# '**' means all files and directories (but not libs or apps)".colorize.dark_gray}
          │ #{"# except those that were mentioned before/after.".colorize.dark_gray}
          │ **
          │ xyz/c.nk
          │ exit.nk
          │
          │ ---
          │ This is the manifest's preamble (delimited by opening & closing
          │ `---`, the latter may be omitted if the preamble is at the end
          │ of the manifest like this one).
          │
          │ The preamble is shown in help mode, for instance in this case
          │ it will be shown if you run `$ novika help foo`.
          ╰

        #{"capability".colorize.bold}

          You can query for a language capability such as `disk` or `ffi`.
          They expose domain-specific words which are not usually needed,
          or are in some way unsafe. Some capabilities are turned on by
          default, so you don't need to request them.

            #{"$ novika ffi my-script.nk".colorize.bold}
            #{"$ novika disk repl".colorize.bold}
            >>> disk:home
            [ '/path/to/home' ]

          Here is a list of capabilities that are available to this
          instance of Novika:

      END

    available_caps = CapabilityCollection.available

    available_caps.select(&.on_by_default?).each do |cap|
      io.puts
      io << "    - " << on << " " << cap.id << " (" << cap.purpose << ")"
    end

    available_caps.reject(&.on_by_default?).each do |cap|
      io.puts
      io << "    - " << cap.id << " (" << cap.purpose << ")"
    end

    io.puts

    io << <<-END

      #{"Autoloading".colorize.underline}

        When no queries are provided, Novika autoloads (implicitly loads)
        the current working directory if it is an app. If it is a lib it
        autoloads it only when a `__lib_wrapper__` app is available in the
        current working directory, or in the environment.

        Novika always autoloads the directory named 'core' in the current
        environment (if it exists of course).

      #{"Novika environment".colorize.underline}

        Novika climbs up the directory tree starting from the current working
        directory, searching for `env/.nk.env`, `.nk.env`, or `.novika`. If
        unsuccessful, Novika also checks `~/.novika`. If the environment
        directory is found, you can use apps, libs, scripts, and directories
        from there globally: no matter where you are in the file tree, you
        can query for them, assuming the environment is somewhere above.

        Environments are isolated from each other. You cannot run a file,
        app, or lib from one environment in another.

          #{"$ mkdir -p env/core foo/bar/baz".colorize.bold}
          #{"$ touch env/.nk.env".colorize.bold}
          #{"# Link so that we have a standard library. Remember that envs".colorize.dark_gray}
          #{"# are isolated from each other; even symlinking to `.novika/core`".colorize.dark_gray}
          #{"# wont't work here.".colorize.dark_gray}
          #{"$ ln -s ~/.novika/core/core.nk env/core/core.nk".colorize.bold}
          #{"$ ln -s ~/.novika/core/system.nk env/core/system.nk".colorize.bold}
          #{"$ echo \"'Hello World' echo\" > env/greet.nk".colorize.bold}
          #{"$ novika greet.nk".colorize.bold}
          Hello World
          #{"$ cd foo/bar/baz".colorize.bold}
          #{"# Note how greet.nk isn't, and wasn't, directly accessible. It's".colorize.dark_gray}
          #{"# being pulled from the environment directory.".colorize.dark_gray}
          #{"$ novika greet.nk".colorize.bold}
          Hello World

        To force Novika to search in the environment instead of the
        current working directory you should prefix your query with '^':

          #{"$ mkdir repl".colorize.bold}
          #{"$ echo \"'Hello from my REPL' echo\" > repl/repl.nk".colorize.bold}
          #{"$ echo -e '---\\nMy REPL help' > repl/.nk.app".colorize.bold}
          #{"$ novika repl".colorize.bold}
          Hello from my REPL
          #{"$ novika help repl".colorize.bold}
          My REPL help
          #{"$ novika ^repl".colorize.bold}
          >>> …
          #{"$ novika help ^repl".colorize.bold}
          novika repl - read-eval-print loop for Novika …

      #{"Examples".colorize.underline}

        Run the Novika REPL:

          #{"$ novika repl".colorize.bold}

        Run the REPL, but load a file first and make it visible to the REPL:

          #{"$ novika foo.nk repl".colorize.bold}

        Create a Novika app (you must be inside an empty directory)

          #{"$ novika create/app".colorize.bold}

        Run the snake example:

          #{"$ novika console examples/snake.new.nk".colorize.bold}

        Get help for an app/lib:

          #{"$ novika help create".colorize.bold}
          #{"$ novika help sdl".colorize.bold}

      #{"Something doesn't seem to work right?".colorize.underline}

        Feel free to file an issue at https://github.com/novika-lang/novika/issues/new.

      END
  end

  # Novika command-line frontend entry point.
  def start(args = ARGV, cwd = Path[ENV["NOVIKA_CWD"]? || Dir.current])
    args = args.dup

    Colorize.enabled = Novika.colorful?

    if args.any?(/^\-{1,2}:?(?:h(?:elp)?|\?)$/)
      help(STDOUT)
      exit(0)
    end

    profiler = nil
    dry_list = false
    dry_list_sm = false
    dry_tree = false
    help_mode = false
    abort_on_permission_request = false

    args.reject! do |arg|
      case arg
      when /^\-:profile(?::([1-9]\d*))?$/
        profiler = Profiler.new($~[1]?.try(&.to_u64) || 16u64)
      when /^\-:dry-list$/
        dry_list = true
      when /^\-:dry-tree$/
        dry_tree = true
      when /^\+:dry-list-sm$/
        dry_list_sm = true
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
      next unless dry_tree

      puts container
    end

    resolver.after_response do |hook|
      if dry_tree
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
      next unless dry_list

      unless dry_list_sm
        puts <<-HINT
        --> Showing environment designations (which environment is going to run which file).
        --> Order matters, and is exactly the execution order.
        HINT

        puts
      end

      hook.each_designation do |designation|
        designation.to_s(STDOUT, sm: dry_list_sm)
        puts
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
