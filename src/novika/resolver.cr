require "csv"

module Dir::Globber
  # I guess all of this is private for a reason, but I still need
  # it for performance!

  def self.each_child_entry(path, &)
    each_child(path) { |entry| yield entry }
  end
end

module Novika::Resolver
  # Specifies the name of the global environment directory.
  ENV_GLOBAL_DIRNAME = ".novika"

  # Specifies the name of the local environment directory.
  ENV_LOCAL_DIRNAME = "env"

  # Specifies the name of the file that is going to be used as the
  # proof that the directory at hand is not simply called 'env',
  # but is actually intended as a Novika environment directory.
  ENV_LOCAL_PROOF_FILENAME = ".nk.env"

  # Specifies the name of the file that will contain saved permissions.
  PERMISSIONS_FILENAME = "permissions"

  # Recursion limit for the resolver. Doesn't have to be big, it's
  # basically file system depth which isn't too big most of the time.
  RESOLVER_RECURSION_LIMIT = 64

  # Selector for `Disk#glob`.
  enum GlobSelector
    # Match all Novika scripts (glob '*.nk')
    Scripts

    # Match all subdirectories (glob '*/')
    Directories

    def to_s(io)
      case self
      in .scripts?     then io << "*" << RunnableScript::EXTENSION
      in .directories? then io << "*/"
      end
    end
  end

  # Represents the permission state of a dependency.
  enum Permission
    Undecided
    Allowed
    Denied
  end

  # Raised when there is an error during resolution.
  class ResolverError < Exception
    # Returns the runnable which is assumed to be the source of
    # this error.
    getter runnable

    def initialize(@message, @runnable : Runnable)
    end
  end

  # Mainly a caching/Novika-specific optimization abstraction over
  # Crystal's `Dir` and `File` methods.
  class Disk
    private record InfoPresence, path : Path, info : File::Info
    private record InfoAbsence

    # Sentinel that stands for an absent Info.
    private InfoAbsent = InfoAbsence.new

    def initialize
      @info = {} of Path => InfoPresence | InfoAbsence
      @envs = {} of Path => Path?
      @globs = {} of Path => Array(GlobEntry)
      @content = {} of Path => String
    end

    # Reads, catches, and returns the `File::Info` object for a
    # specific *path*. Returns nil if there is nothing at *path*.
    # The absence is also cached. The returned file info is guaranteed
    # to contain a real path.
    #
    # *path* is assumed to be absolute and normalized.
    def info?(path : Path) : InfoPresence?
      # If there's matching cached info, return that.
      if presence = @info[path]?
        return presence.as?(InfoPresence)
      end

      # If the entry is absent on disk, cache that and
      # bail out.
      unless info = File.info?(path, follow_symlinks: false)
        @info[path] = InfoAbsent
        return
      end

      # If the entry exists but is a symlink, resolve its
      # real path and repeat.
      if info.symlink?
        real = Path[File.realpath(path)]
        info = File.info?(real, follow_symlinks: false)
        presence = info.try { |it| InfoPresence.new(real, it) } || InfoAbsent
        @info[real] = @info[path] = presence
      else
        @info[path] = presence = InfoPresence.new(path, info)
      end

      presence.as?(InfoPresence)
    end

    # If *path* points to a file, returns *path*. Otherwise,
    # returns nil.
    def file?(path : Path) : Path?
      return unless presence = info?(path)
      return unless presence.info.file?

      Path[presence.path]
    end

    # If *path* points to a directory, returns *path*. Otherwise,
    # returns nil.
    def dir?(path : Path) : Path?
      return unless presence = info?(path)
      return unless presence.info.directory?

      Path[presence.path]
    end

    # Returns the content of the file *path* points to.
    #
    # Raises if *path* doesn't point to a file.
    def read(path : Path) : String?
      @content[path] ||= File.read(path)
    end

    private struct GlobEntry
      # Returns whether this entry is a directory.
      getter? directory

      def initialize(@path : Path, @directory : Bool)
      end

      # Returns whether this entry is a Novika script.
      def script?
        !directory? && @path.extension == RunnableScript::EXTENSION
      end

      # Returns whether *selector* applies to this entry.
      def selected_by?(selector : GlobSelector)
        case selector
        in .scripts?     then script?
        in .directories? then directory?
        end
      end

      # Calls *fn* if *selector* applies to this entry.
      def if(selector : GlobSelector, *, call fn : Path ->)
        return unless selected_by?(selector)

        fn.call(@path)
      end
    end

    # The cached version of glob. Calls *fn* for every cached glob
    # entry that matches *selector*.
    private def glob(entries : Array(GlobEntry), selector : GlobSelector, fn : Path ->)
      entries.each &.if(selector, call: fn)
    end

    # Branches between the cached and disk-y version of glob.
    private def glob(origin : Path, selector : GlobSelector, fn : Path ->)
      if entries = @globs[origin]?
        glob(entries, selector, fn)
        return
      end

      entries = @globs[origin] = [] of GlobEntry

      Dir::Globber.each_child_entry(origin) do |entry|
        path = origin / entry.name

        directory = entry.dir?
        if directory.nil?
          next unless presence = info?(path)
          next if directory = presence.info.directory?

          path = presence.path
        end

        entry = GlobEntry.new(path, directory)
        entries << entry

        entry.if(selector, call: fn)
      end
    end

    # A simpler, Novika- and `Disk`-specific globbing mechanism.
    #
    # Calls *fn* with paths in *origin* directory that match the
    # given *selector*.
    def glob(origin : Path, selector : GlobSelector, &fn : Path ->)
      glob(origin, selector, fn)
    end

    # Determines and returns the path to the environment directory,
    # if any. Otherwise, returns nil.
    #
    # Climbs up from *origin* until encountering:
    #
    # - A file named '.nk.env'
    # - A directory named 'env' containing a file named '.nk.env'
    # - A directory named '.novika'
    def env?(origin : Path) : Path?
      @envs[origin] ||= begin
        env : Path?

        return origin if file?(origin / ENV_LOCAL_PROOF_FILENAME)
        return Path[File.realpath(env)] if dir?(env = origin / ENV_GLOBAL_DIRNAME)
        return Path[File.realpath(env)] if dir?(env = origin / ENV_LOCAL_DIRNAME) && file?(env / ENV_LOCAL_PROOF_FILENAME)
        return if origin == origin.root

        env?(origin.parent)
      end
    end
  end

  # Obtaining a set of resolution objects from an initial list of
  # queries is the central goal of the resolver.
  #
  # A resolution object points to a script and lists its dependencies.
  # Furthermore, a resolution object also stores its so-called
  # runnable *sources*, which are `RunnableScript` objects that it
  # was derived from.
  struct Resolution
    # Includers can be listed as dependencies in a `Resolution`.
    module Dependency
      # Represents the signature of a dependency.
      alias Signature = {String, String}

      # Provides the includer with an implementation of `Dependency#prompt?`
      # provided it implements `label`.
      module DefaultPrompt
        # Returns a user-friendly string representation of this
        # dependency. The returned string should be suitable for
        # displaying to the user in a prompt.
        #
        # *server* is the server that will somehow use the label.
        abstract def label(server : PermissionServer) : String

        # Returns a user-friendly description of this dependency, or
        # nil if none can be given. The returned description should
        # be suitable for displaying to the user in a prompt, and
        # should read well after "which", as in "which exposes this
        # and that", "which creates this and that", etc.
        #
        # *server* is the server that will somehow use the description
        # in case it is present.
        def description?(server : PermissionServer) : String?
        end

        def prompt?(server : PermissionServer, *, for group : RunnableGroup) : Permission
          label = label(server)

          prompt = String.build do |io|
            io << "Allow " << group.abspath << " to load " << label
            if description = description?(server)
              io << ", which " << description
            end
            io << "? [" << "y".colorize.underline << " yes | " << "?".colorize.underline << " help | <other> no]"
          end

          loop do
            case server.ask?(prompt)
            when .nil?
              next
            when /^\s*([Yy?])\s*$/
              return Permission::Allowed unless $1 == "?"

              # Output backtrace so that the user sees where the
              # need for this dependency came from.
              answer = String.build do |io|
                backtrace(io, indent: 2, annex: "Showing where #{label} was referenced.")

                io.puts
              end

              server.answer(answer)

              next
            end

            return Permission::Denied
          end
        end
      end

      # Returns the signature of this dependency which can be used
      # to identify it, specifically in the 'permissions' file.
      abstract def signature(group : RunnableGroup) : Signature

      # Enables this dependency in the given capability collection *caps*
      # if this dependency is `allowed?`.
      abstract def enable(*, in caps : CapabilityCollection)

      # Promps the user for whether the use of this dependency should
      # be allowed to *group*, and returns the resulting `Permission`
      # state.
      abstract def prompt?(server : PermissionServer, *, for group : RunnableGroup) : Permission

      @permission = Permission::Undecided

      # Returns whether this dependency is allowed. Depends on the permission
      # state of this dependency, which is normally set by `PermissionServer`.
      def allowed? : Bool
        @permission.allowed?
      end

      # Sets the permission state of this dependency to "allowed".
      def allow
        @permission = Permission::Allowed
      end

      # Sets the permission state of this dependency to "denied".
      def deny
        @permission = Permission::Denied
      end

      # Communicates with *server* in order to determine whether
      # this dependency is allowed for the given *group*.
      #
      # See `PermissionServer#request` for more information.
      def request(server : PermissionServer, *, for group : RunnableGroup)
        return unless @permission.undecided?

        # Ask the server if this dependency is explicit. A dependency
        # is considered explicit when it is specified in the arguments
        # by hand.
        if server.explicit?(self)
          @permission = Permission::Allowed
          return
        end

        @permission = server.query_permission?(group, self)
      end
    end

    @abspath : Path

    # Initializes a runnable resolution for the given runnable *script* and a
    # set of resolution dependency objects *deps*.
    def initialize(script : RunnableScript, @deps : Set(Dependency))
      @abspath = script.abspath
      @sources = [script]
    end

    # Appends the dependencies of this resolution to *deps*, source scripts
    # of this resolution to *sources*.
    def dump!(deps : Set(Dependency)? = nil, sources : Array(RunnableScript)? = nil)
      deps.try &.concat(@deps)
      sources.try &.concat(@sources)
    end

    # Mutably merges this and *other* resolutions.
    def merge!(other : Resolution) : self
      other.dump!(@deps, @sources)

      self
    end

    # Yields dependencies of this resolution.
    def each_dependency(& : Dependency ->)
      @deps.each { |dep| yield dep }
    end

    # Yields all `RunnableGroup`s from the ancestry of source scripts of
    # this resolution. Does not yield the same group twice (sameness is
    # determined with `==`/hash).
    def each_source_group(& : RunnableGroup ->)
      visited = Set(RunnableGroup).new

      @sources.each do |source|
        source.each_ancestor do |ancestor|
          next unless ancestor.is_a?(RunnableGroup)
          next if ancestor.in?(visited)
          yield ancestor
          visited << ancestor
        end
      end
    end

    # Runs this resolution's script with *engine*. Script block
    # (aka *file block*) is set to be a child of *toplevel*.
    def run(engine : Engine, toplevel : Block)
      source = File.read(@abspath)

      file_block = Block.new(toplevel).slurp(source)
      file_block.at(Word.new("__path__"), Quote.new(@abspath.parent.to_s))
      file_block.at(Word.new("__file__"), Quote.new(@abspath.to_s))

      instance = file_block.instance
      instance.schedule!(engine, stack: Block.new)

      engine.exhaust

      toplevel.import!(from: instance)
    end

    def to_s(io)
      io << @abspath << " (" << @deps.join(", ") << ") ← [" << @sources.join(" | ") << "]"
    end

    # Two resolutions are considered equal when they point to the
    # same script.
    def_equals_and_hash @abspath
  end

  # Represents an ordered set of resolution objects.
  struct ResolutionSet
    def initialize
      @resolutions = [] of Resolution
    end

    # Returns the amount of resolutions in this resolution set.
    def size
      @resolutions.size
    end

    # Returns whether there are no resolutions in this resolution set.
    def empty?
      size.zero?
    end

    # Appends a *resolution* to this set. In case this set already
    # contains a resolution for the same path, the two resolutions
    # are merged via `Resolution#merge!`.
    def append(resolution : Resolution)
      if index = @resolutions.index(resolution)
        @resolutions[index] = @resolutions[index].merge!(resolution)
        return
      end

      @resolutions << resolution
    end

    # Appends an entire resolution *set* at once. Essentially the
    # same as appending each `Resolution` from *set*.
    def append(set : ResolutionSet)
      set.each { |resolution| append(resolution) }
    end

    # Yields resolutions in this resolution set.
    def each(& : Resolution ->)
      @resolutions.each { |resolution| yield resolution }
    end

    # Yields all `RunnableGroup` objects that have contributed
    # to this resolution set. The yielded groups can repeat.
    def each_group(& : RunnableGroup, Resolution ->)
      each do |resolution|
        resolution.each_source_group do |group|
          yield group, resolution
        end
      end
    end

    # Returns an array of `RunnableGroup` objects that have
    # contributed to this resolution set. Objects in the array
    # can repeat.
    def groups : Array(RunnableGroup)
      groups = [] of RunnableGroup
      each_group do |group|
        groups << group
      end
      groups
    end

    # Returns whether all resolutions from this set come from the
    # same `RunnableGroup`. `RunnableGroup` to match is selected by
    # applying the block to all `RunnableGroup`s in this set.
    def all_come_from_same?(& : RunnableGroup -> Bool) : Bool
      return false if empty?

      matching = groups.select! { |group| yield group }
      return false if size > matching.size

      first = matching.first
      return false unless matching.all? &.same?(first)

      true
    end

    # Returns whether all resolutions in this set come from the
    # same application `RunnableGroup`.
    def app? : Bool
      all_come_from_same?(&.app?)
    end

    # Returns whether all resolutions in this set come from the
    # same library `RunnableGroup`.
    def lib? : Bool
      all_come_from_same?(&.lib?)
    end

    # Yields all `RunnableGroup` objects that have contributed
    # to this resolution set. The yielded groups do not repeat.
    def each_unique_group(& : RunnableGroup ->)
      visited = Set(RunnableGroup).new

      each_group do |group|
        next if group.in?(visited)
        yield group
        visited << group
      end
    end

    # Yields application `RunnableGroup`s that have contributed
    # to this resolution set.
    def each_unique_app(& : RunnableGroup ->)
      each_unique_group do |group|
        next unless group.app?
        yield group
      end
    end

    # Yields library `RunnableGroup`s that have contributed
    # to this resolution set.
    def each_unique_lib(& : RunnableGroup ->)
      each_unique_group do |group|
        next unless group.lib?
        yield group
      end
    end

    # Returns an array of unique application `RunnableGroup`s that have
    # contributed to this resolution set.
    def unique_apps : Array(RunnableGroup)
      unique_apps = [] of RunnableGroup
      each_unique_app do |app|
        unique_apps << app
      end
      unique_apps
    end

    # Returns an array of unique library `RunnableGroup`s that have
    # contributed to this resolution set.
    def unique_libs : Array(RunnableGroup)
      unique_libs = [] of RunnableGroup
      each_unique_lib do |lib_|
        unique_libs << lib_
      end
      unique_libs
    end

    # Yields resolutions that were contributed by the given *group*.
    def each_from_group(group : RunnableGroup, & : Resolution ->)
      each do |resolution|
        accept = false
        resolution.each_source_group do |other|
          next unless group == other
          break accept = true
        end
        next unless accept
        yield resolution
      end
    end

    # Yields `Resolution::Dependency` objects and a `ResolutionSet`
    # of their dependents.
    def each_unique_dependency_with_dependents(& : Resolution::Dependency, ResolutionSet ->)
      map = {} of Resolution::Dependency => ResolutionSet

      each do |resolution|
        resolution.each_dependency do |dep|
          set = map[dep] ||= ResolutionSet.new
          set.append(resolution)
        end
      end

      map.each { |dep, set| yield dep, set }
    end

    def to_s(io)
      io.puts("ResolutionSet")

      each do |resolution|
        io << " | " << resolution
        io.puts
      end
    end
  end

  # Base class of all runnables.
  #
  # The main basic property of all runnables is that they can be
  # *rewritten* into other runnables, oftentimes of a more specific
  # kind. Additionally, runnable objects are also the head of
  # their history linked list, allowing clients to observe how
  # the runnable of interest came to be.
  abstract class Runnable
    # Represents a `Runnable` ancestor.
    module Ancestor
      # Returns the ancestor.
      abstract def ancestor? : Ancestor?
    end

    include Ancestor

    # Represents a terminal runnable, meaning a runnable that cannot
    # be rewritten any further.
    module Terminal
      def specialize(root : RunnableRoot, container : RunnableContainer)
        container.append(self)
      end
    end

    # Represents a runnable with datum of type *T*. This module
    # assigns no intrinsic meaning to "datum"; includers are free
    # to choose it, as well as its type *T*.
    #
    # The only real consequence of including this module is that
    # equality and hash methods will be defined. These methods
    # will delegate comparison/hashing to the datum(s) at hand.
    module HasDatum(T)
      @datum : T

      def_equals_and_hash @datum
    end

    getter? ancestor : Ancestor?

    def initialize(@ancestor : Ancestor? = nil)
    end

    # Yields ancestors of this runnable.
    #
    # By tracing the ancestry of `self`, you are exploring how it
    # came to be.
    def each_ancestor(& : Ancestor ->)
      runnable = @ancestor
      while runnable
        yield runnable
        runnable = runnable.ancestor?
      end
    end

    # Appends ancestors leading to this runnable to *io*.
    #
    # *indent* can be used to specify the amount of whitespace
    # preceding each line.
    #
    # *annex* is the additional bit of text displayed below the
    # backtrace. For instance, in case of an error, it can contain
    # the error message.
    def backtrace(io : IO, indent : Int32 = 0, annex : String? = nil)
      backtrace = [self] of Ancestor

      each_ancestor do |ancestor|
        backtrace.unshift(ancestor)
      end

      io << "  ┬\n"

      ws = " " * indent
      backtrace.each do |runnable|
        io << ws << "╿ in "
        if runnable.is_a?(Resolver::RunnableContainer)
          content = String.build { |inner| runnable.to_s(inner, lead: 0, indent: indent + 2) }

          skip = true
          content.each_line(chomp: true) do |line|
            if skip
              io.puts(line)
              skip = false
              next
            end
            io << "  │" << line << '\n'
          end
        else
          io << runnable << '\n'
        end
      end

      return unless annex

      io << "  │\n ╰┴─ " << annex << '\n'
    end

    # Yields an `IO` where you can write the *annex*, otherwise
    # the same as `backtrace`.
    def backtrace(*args, **kwargs, & : IO ->)
      annex = String.build { |io| yield io }

      backtrace(*args, **kwargs, annex: annex)
    end

    # Returns an array with contained runnables. If none,
    # returns an array with `self`.
    def constituents : Array(Runnable)
      [self] of Runnable
    end

    # Further specializes this runnable. Appends the specialized runnable
    # to (or interacts in some other way with) *container*. The latter is
    # assumed to be incomplete (or partially complete, which is really
    # the same thing).
    #
    # *root* is the runnable root object. It is mainly used for flags and
    # thorough rewriting.
    abstract def specialize(root : RunnableRoot, container : RunnableContainer)
  end

  alias Query = Path | String

  # Runnable queries are one of the most generic kinds of runnables,
  # and specialize themselves through `RunnableContainer#classify?`.
  class RunnableQuery < Runnable
    include HasDatum(Query)

    def initialize(@datum, ancestor = nil, @else : Runnable? = self)
      super(ancestor)
    end

    def specialize(root : RunnableRoot, container : RunnableContainer)
      if runnable = container.classify?(@datum, ancestor: self)
        container.append(runnable)
        return
      end

      return unless alt = @else

      container.append(alt)
    end

    def to_s(io)
      io << "Query[" << @datum << "]"
    end
  end

  # Selectors get rewritten to matching file system entries from
  # the directory of the container that they are specialized by.
  class RunnableSelector < Runnable
    include HasDatum(GlobSelector)

    def initialize(@datum, @reject = Set(String).new, ancestor = nil)
      super(ancestor)
    end

    def specialize(root : RunnableRoot, container : RunnableContainer)
      container.each_sorted_path(@datum) do |path|
        basename = path.basename

        next if basename.in?(@reject)
        next if basename.starts_with?('_')

        case @datum
        in .scripts?
          next unless path.extension == RunnableScript::EXTENSION

          runnable = RunnableScript.new(path, ancestor: self)
        in .directories?
          runnable = RunnableDir.new(path, ancestor: self)

          if basename == "core"
            container.prepend(runnable)
            next
          end
        end

        container.append(runnable)
      end
    end

    def to_s(io)
      io << "Forall[" << @datum << " ∉ {" << @reject.join(',') << "}]"
    end
  end

  # Capabilities represent the requirements of a Novika script,
  # library, or application, regarding interpreter features that
  # are needed in order for that script, library, or application
  # to work correctly.
  #
  # Capabilities are terminal, which means they do not get
  # rewritten any further.
  class RunnableCapability < Runnable
    include HasDatum(String)
    include Terminal
    include Resolution::Dependency
    include Resolution::Dependency::DefaultPrompt

    def initialize(@datum, ancestor = nil)
      super(ancestor)
    end

    def signature(group : RunnableGroup) : Signature
      {group.abspath.to_s, @datum}
    end

    def label(server : PermissionServer) : String
      "capability #{@datum.colorize.bold}"
    end

    def description?(server : PermissionServer) : String?
      server.brief(self)
    end

    def purpose(*, in caps : CapabilityCollection)
      unless cls = caps.get_capability_class?(@datum)
        raise "BUG: capability runnable for which there is no capability class"
      end

      cls.purpose
    end

    def enable(*, in caps : CapabilityCollection)
      return unless allowed?
      return if caps.has_capability_enabled?(@datum)

      caps.enable(@datum)
    end

    def to_s(io)
      io << "Capability[" << @datum << "]"
    end
  end

  # Runnable representation of a shared object. Shared objects
  # are accessed via FFI Novika-side.
  #
  # Shared objects are terminal, which means they do not get
  # rewritten any further.
  class RunnableSharedObject < Runnable
    include HasDatum(Path)
    include Terminal
    include Resolution::Dependency
    include Resolution::Dependency::DefaultPrompt

    {% if flag?(:windows) %}
      EXTENSION = ".dll"
    {% elsif flag?(:darwin) %}
      EXTENSION = ".dylib"
    {% elsif flag?(:unix) %}
      EXTENSION = ".so"
    {% else %}
      {{ raise "Could not determine shared object extension for OS" }}
    {% end %}

    def initialize(@datum, ancestor = nil)
      super(ancestor)
    end

    # Returns the id of this shared object.
    #
    # The id is made by taking the stem of path to the object and
    # stripping it of the lib prefix, if it has one. For example,
    # given `/lib/libmath.so` or `/lib/math.so`, the id would be
    # `math` in both cases.
    def id
      @datum.stem.lchop("lib")
    end

    def signature(group : RunnableGroup) : Signature
      {group.abspath.to_s, @datum.to_s}
    end

    def label(server : PermissionServer) : String
      "shared object #{@datum.colorize.bold}"
    end

    def enable(*, in caps : CapabilityCollection)
      return unless allowed?
      return if caps.has_library?(id = self.id)

      caps << Library.new(id, @datum)
    end

    def to_s(io)
      io << "SharedObject[" << @datum << "]"
    end
  end

  # Represents a Novika script, specifically a '.nk' file.
  #
  # Runnable scripts are terminal, which means they do not get
  # rewritten any further.
  class RunnableScript < Runnable
    include HasDatum(Path)
    include Terminal

    EXTENSION = ".nk"

    def initialize(@datum, ancestor = nil)
      super(ancestor)
    end

    # Returns the absolute path to this script.
    def abspath
      raise "BUG: script datum is not an absolute path" unless @datum.absolute?

      @datum
    end

    def to_s(io)
      io << "Script[" << @datum
      each_ancestor do |ancestor|
        io << " ← " << ancestor
      end
      io << "]"
    end
  end

  # Represents a directory in the file system. At this point it
  # is still unknown whether the directory is a Novika library,
  # application, or simply that - a directory.
  #
  # Runnable directories get rewritten to `RunnableGroup`s, which
  # are aware of the presence or absence of manifest(s).
  class RunnableDir < Runnable
    include HasDatum(Path)

    def initialize(@datum, ancestor = nil)
      super(ancestor)
    end

    def specialize(root : RunnableRoot, container : RunnableContainer)
      group = RunnableGroup.allocate
      manifest = Manifest.find(root.disk, @datum, ancestor: group)
      group.initialize(@datum, manifest, ancestor: @ancestor)
      container.append(group)
    end

    def to_s(io)
      io << "Dir[" << @datum << "]"
    end
  end

  # Base class of `ScriptsSlot` (known to the user as `*`), `SubtreeSlot`
  # (known to the user as `**`), and `ChildSlot` (`<>`).
  #
  # Slots act as mere sentinels (or placeholders). They get `replace`d
  # with runnable containers that hold the appropriate runnables during
  # postprocessing of the manifest file, provided the latter has some
  # slots to begin with.
  #
  # The use of slot literals `*`, `**`, and `<>` is only allowed inside
  # manifest files.
  #
  # Even though using several `*`s is allowed, it is pointless to do
  # so because the first `*` (or `**` for that matter) will 'consume'
  # all remaining file system entries, leaving none to the second,
  # third, etc. `*` or `**`.
  abstract class Slot < Runnable
    include Terminal

    # Replaces any occurences of this slot in *local* with a
    # container holding the runnables this slot stands for.
    #
    # *manifest* is the manifest that contains this slot.
    #
    # *group* is the `RunnableGroup` of the manifest that contains
    # this slot.
    #
    # Returns the next global container.
    abstract def replace(
      root : RunnableRoot,
      group : RunnableGroup,
      manifest : Manifest::Present,
      global : RunnableContainer,
      local : RunnableContainer
    ) : RunnableContainer
  end

  # Slot (placeholder) that stands for "all not otherwise mentioned
  # Novika scripts" in the container's directory, represented with `**`.
  class ScriptsSlot < Slot
    def replace(
      root : RunnableRoot,
      group : RunnableGroup,
      manifest : Manifest::Present,
      global : RunnableContainer,
      local : RunnableContainer
    ) : RunnableContainer
      mentioned = global.paths

      # Fill a shallow container with Novika scripts from the
      # directory where the manifest is located.
      content = local.child(manifest.directory, shallow: true)

      root.disk.glob(manifest.directory, GlobSelector::Scripts) do |datum|
        next if datum.in?(mentioned)

        content.append RunnableScript.new(datum, ancestor: self)
      end

      local.replace(self, content)

      global
    end

    def to_s(io)
      io << "Slot[*]"
    end
  end

  # Slot (placeholder) that stands for "all not otherwise mentioned
  # Novika scripts and directories in the subtree (recursively),
  # except for Novika application and library directories",
  # represented with `**`.
  class SubtreeSlot < Slot
    def replace(
      root : RunnableRoot,
      group : RunnableGroup,
      manifest : Manifest::Present,
      global : RunnableContainer,
      local : RunnableContainer
    ) : RunnableContainer
      mentioned = global.paths

      # Note how we ignore apps and libs. This is necessary due to
      # the use of `layout` as it is unaware of our intent.
      content = local.child(manifest.directory, shallow: true)
      content.allow? { |r| !(r.is_a?(RunnableGroup) && (r.app? || r.lib?)) }

      local.replace(self, content)

      manifest.layout(content, group)

      # Rewrite for good measure. We don't need a thorough rewrite
      # here because `layout` is file system-only, and all files in the
      # file system exist by definition.
      content.rewrite

      # Leave only containers for non-application directories, and
      # optionally those scripts that aren't already specified (incl.
      # by the scripts slot, which has higher precedence and is therefore
      # expanded before the subtree slot).
      content.recursive_select! do |runnable|
        case runnable
        when RunnableScript
        when RunnableContainer
          next false if runnable.app? || runnable.lib?
        end

        # It'd be more elegant to have `else next false` above but
        # Crystal doesn't get that.
        unless runnable.is_a?(RunnableScript) || runnable.is_a?(RunnableContainer)
          next false
        end

        !runnable.abspath.in?(mentioned)
      end

      global
    end

    def to_s(io)
      io << "Slot[**]"
    end
  end

  # Slot (placeholder) that stands for "runnables of whomever
  # inherits me".
  class ChildSlot < Slot
    def replace(
      root : RunnableRoot,
      group : RunnableGroup,
      manifest : Manifest::Present,
      global : RunnableContainer,
      local : RunnableContainer
    ) : RunnableContainer
      # Create an empty container, allow everything in it -- make
      # it opaque to filter inheritance.
      content = global.child

      # Replace myself with the container.
      local.replace(self, content)

      # Next manifests should continue filling the container.
      content
    end

    def to_s(io)
      io << "Slot[<>]"
    end
  end

  # Includers are manifests in `RunnableGroup`s.
  #
  # Manifests exist mainly to allow to specify alternative load
  # order. They are designed to be hidden so as to not interfere
  # with/clutter the user's file tree.
  module Manifest
    # Creates and returns a manifest object if *path* contains
    # a manifest. Otherwise, returns nil.
    def self.find(disk : Disk, path : Path, ancestor = nil) : Manifest
      Lib.find?(disk, path, ancestor) || App.find?(disk, path, ancestor) || Absent.new
    end

    # Populates *container* with runnables from *group* according
    # to this manifest's default layout.
    #
    # * For application manifests, it's `* ** entry.nk`.
    # * For library manifests and directories with no manifest, it's
    #   `entry.nk * **`.
    def layout(container : RunnableContainer, group : RunnableGroup)
      entry = group.entry_name

      container.append(RunnableQuery.new(group.abspath / entry, ancestor: group, else: nil))
      container.append(RunnableSelector.new(GlobSelector::Scripts, reject: Set{entry}, ancestor: group))
      container.append(RunnableSelector.new(GlobSelector::Directories, ancestor: group))
    end

    # Populates *container* with runnables from *origin* according
    # to the content of the manifest.
    #
    # * If there is no explicit `*` or `**`, `**` is automatically
    #   inserted at the very beginning of the manifest regardless
    #   of whether it is an application manifest or a library manifest.
    #
    # * A directory with no manifest is laid out directly using `layout`,
    #   since there is no "manifest content" to speak of.
    def populate(root : RunnableRoot, container : RunnableContainer, origin : RunnableGroup)
      subtree = container.child(shallow: true)
      subtree.allow? { |r| !(r.is_a?(RunnableGroup) && (r.app? || r.lib?)) }
      container.append(subtree)

      layout(subtree, origin)
    end
  end

  # Represents the presence of a manifest.
  module Manifest::Present
    include Runnable::Ancestor

    # Path pointing to the manifest itself.
    @path : Path

    # Returns a path that points to the directory where this
    # manifest is located.
    def directory
      @path.parent
    end

    # Climbs the manifest inheritance chain. Yields manifests
    # starting from `self` and up to the higest manifest in
    # the chain, followed by `true` or `false` for whether the
    # yielded manifest is `self`.
    private def climb(root : RunnableRoot, origin : RunnableGroup, &)
      current = directory.parent
      manifest = self

      yield manifest, origin, true

      while manifest = Manifest::Lib.find?(root.disk, current, ancestor: manifest)
        yield manifest, RunnableGroup.new(current, manifest), false

        current = current.parent
      end
    end

    # Expands preprocessor expressions in *content*. Returns the
    # new content, where preprocessor expressions are substituted
    # with the expanded values.
    #
    # *root* is the runnable root, it is mainly needed to check flags.
    private def expand(root : RunnableRoot, content : String) : String
      content.gsub(/\[([^\]]+)\]/) do |pexp|
        case $1
        when /^\s*(\w+(?:\s*,\s*\w+)*)\s*\|\s*(\w+(?:\s*,\s*\w+)*)$/
          flags = $1.split(/\s*,\s*/, remove_empty: true)
          blocks = $2.split(/\s*,\s*/, remove_empty: true)
          next pexp unless flags.size == blocks.size

          branches = Hash.zip(flags, blocks)
          branch = branches["_"]?

          root.each_true_flag do |flag|
            next unless block = branches[flag]?
            break branch = block
          end

          branch || ""
        end
      end
    end

    # Splits *content* into a list of string fragments, which are almost
    # the same as runnable queries.
    private def to_fragments(content : String) : Array(String)
      content.split(/(?:#[^\n]*)?\s+/, remove_empty: true)
    end

    # Converts each string fragment in *fragments* into a `Runnable`.
    # Returns the resulting array of `Runnable`s.
    private def to_runnables(fragments : Array(String)) : Array(Runnable)
      fragments.map do |fragment|
        case fragment
        when "*"  then ScriptsSlot.new(ancestor: self)
        when "**" then SubtreeSlot.new(ancestor: self)
        when "<>" then ChildSlot.new(ancestor: self)
        else
          RunnableQuery.new(fragment, ancestor: self)
        end
      end
    end

    # Reads the manifest content from the disk, expands preprocessor
    # expressions in it (if any), and it into fragments. Returns the
    # resulting array of fragments.
    protected def fragments(*, within root : RunnableRoot) : Array(String)
      content = root.disk.read(@path)
      content = expand(root, content)
      to_fragments(content)
    end

    # Processes *fragments* of a manifest: populates *container*
    # with matching runnables.
    #
    # *inherited* stands for whether `self` was inherited. This
    # results in more restrictive automatic gathering of files.
    protected def process(
      root : RunnableRoot,
      group : RunnableGroup,
      global : RunnableContainer,
      directives : Array(String),
      fragments : Array(String),
      inherited : Bool
    ) : RunnableContainer
      # Create a local container for this manifest specifically. Remember
      # that multiple manifests  can populate the same *container* through
      # inheritance, therefore, some bit of separation is necessary.
      local = global.child(directory, shallow: true)
      global.append(local)

      # Disallow apps inside manifests.
      local.allow?(warn: true) { |r| !(r.is_a?(RunnableGroup) && r.app?) }

      # Get an array of queries.
      queries = to_runnables(fragments)

      # Find slots there, if they're there at all.
      slots = queries.select(Slot)

      # Populate the manifest container with queries.
      local.append(queries)

      # If no explicit subtree slot, create one & make it so that
      # it is loaded first (this seems to make most sense).
      unless slots.any?(SubtreeSlot) || inherited || directives.includes?("nolayout")
        slot : SubtreeSlot
        slot = SubtreeSlot.new(ancestor: self)
        slots.unshift(slot)
        local.prepend(slot)
      end

      # Perform a thorough rewrite. This guarantees the child
      # *truly* cannot be rewritten any further, regardless of
      # origins etc.
      root.thorough_rewrite(local)

      cons = nil

      slots.each do |slot|
        ingress = slot.replace(root, group, self, global, local)

        next if cons
        next if ingress.same?(global)

        # Set cons to the first "ingress" container different from
        # the global container.
        cons = ingress
      end

      cons || global
    end

    # A set of allowed manifest directives.
    DIRECTIVES = Set{"noinherit", "nolayout"}

    def populate(root : RunnableRoot, container : RunnableContainer, origin : RunnableGroup)
      # We have to run manifests in grandparent-parent-child-etc. order,
      # but we climb in child-parent-grandparent order and, moreover,
      # child, parent, etc. can interrupt climbing with 'noinherit' or
      # by being of a non-inheritable kind, such as '.nk.app' parent
      # of '.nk.lib'.
      manifests = [] of {Manifest::Present, RunnableGroup, Array(String), Array(String), Bool}

      climb(root, origin) do |manifest, group, isself|
        directives, fragments = manifest.fragments(within: root).partition &.in?(DIRECTIVES)
        manifests << {manifest, group, directives, fragments, !isself}

        break if directives.includes?("noinherit")
      end

      manifests.reverse_each do |manifest, group, directives, fragments, inherited|
        container = manifest.process(root, group, container, directives, fragments, inherited)
      end
    end

    def to_s(io)
      io << "Manifest[" << @path << "]"
    end
  end

  # Represents an application manifest.
  class Manifest::App
    include Manifest
    include Manifest::Present

    FILENAME = ".nk.app"

    getter? ancestor : Runnable::Ancestor?

    # Creates a new application manifest.
    #
    # *path* is a *normalized* path pointing to the manifest.
    def initialize(@path : Path, @ancestor)
    end

    # Creates and returns an application manifest object if
    # *path* contains an application manifest. Otherwise,
    # returns nil.
    def self.find?(disk : Disk, path : Path, ancestor = nil)
      return unless datum = disk.file?(path / FILENAME)

      new(datum, ancestor)
    end

    def layout(container : RunnableContainer, group : RunnableGroup)
      entry = group.entry_name

      container.append(RunnableSelector.new(GlobSelector::Scripts, reject: Set{entry}, ancestor: group))
      container.append(RunnableSelector.new(GlobSelector::Directories, ancestor: group))
      container.append(RunnableQuery.new(group.abspath / entry, ancestor: group, else: nil))
    end
  end

  # Represents a library manifest.
  class Manifest::Lib
    include Manifest
    include Manifest::Present

    FILENAME = ".nk.lib"

    getter? ancestor : Runnable::Ancestor?

    # Creates a new library manifest.
    #
    # *path* is a *normalized* path pointing to the manifest.
    def initialize(@path : Path, @ancestor)
    end

    # Creates and returns an library manifest object if *path*
    # contains a library manifest, returns nil.
    def self.find?(disk : Disk, path : Path, ancestor = nil)
      return unless datum = disk.file?(path / FILENAME)

      new(datum, ancestor)
    end
  end

  # Represents the absence of a manifest.
  struct Manifest::Absent
    include Manifest
  end

  # A runnable group is a directory with or without a manifest:
  # that is, a directory with awareness of whether it is an
  # application, library, or simply that - a directory.
  #
  # In other words, runnable groups are directories with a specific
  # declared runnable *layout*. `RunnableDir`s, on the other hand,
  # have no declared layout.
  #
  # Runnable groups are rewritten to properly ordered (laid out)
  # `RunnableContainer`s.
  class RunnableGroup < Runnable
    include HasDatum(Path)

    # Creates a new runnable group.
    #
    # *manifest* is the layout manifest of this group. Layout manifests
    # (manifests for short) control how the order of runnables in this
    # group.
    #
    # *datum* is a *normalized* path to the group (a directory).
    def initialize(@datum, @manifest : Manifest, ancestor = nil)
      super(ancestor)
    end

    # Returns whether this group represents an app (is laid out
    # according to a '.nk.app' manifest).
    def app? : Bool
      @manifest.is_a?(Manifest::App)
    end

    # Returns whether this group represents a lib (is laid out
    # according to a '.nk.lib' manifest).
    def lib? : Bool
      @manifest.is_a?(Manifest::Lib)
    end

    # Constructs and returns entry filename for this group.
    #
    # For instance, if this group's directory is '/path/to/foo',
    # then its entry filename will be 'foo.nk'.
    def entry_name : String
      "#{@datum.stem}.nk"
    end

    # Returns an absolute path to this group.
    def abspath
      raise "BUG: group datum is not an absolute path" unless @datum.absolute?

      @datum
    end

    def specialize(root : RunnableRoot, container : RunnableContainer)
      child = container.child(@datum)
      container.append(child)

      # Ask our manifest to populate the container. The decision on how to
      # lay out files, directories, apps, libraries and so on inside this
      # group is entirely up to the manifest.
      @manifest.populate(root, child, origin: self)
    end

    def to_s(io)
      case
      when app? then io << "App"
      when lib? then io << "Lib"
      else
        io << "Group"
      end

      io << "[" << @datum << "]"
    end
  end

  # A runnable container is an *ordered*, arbitrarily *filtered*
  # collection of runnables - and a runnable itself.
  class RunnableContainer < Runnable
    # :nodoc:
    record Filter, fn : (Runnable -> Bool), warn : Bool do
      delegate :call, to: fn
    end

    # Returns whether this container is shallow.
    getter? shallow : Bool

    # Initializes a new runnable container for the given *dir*ectory.
    #
    # *parent* is the parent runnable container. You don't normally need
    # to specify it. Prefer to call `child` on the parent instead.
    #
    # *shallow* specifies whether the container is shallow.
    def initialize(
      @root : RunnableRoot,
      @dir : Path,
      @parent : RunnableContainer? = nil,
      @shallow = false,
      ancestor = nil
    )
      super(ancestor)

      @filters = [] of Filter
      @runnables = [] of Runnable
    end

    # Recursively collects filters applicable to this container,
    # starting from this container, to *arr*. Returns *arr*.
    protected def collect_filters(arr : Array(Filter))
      arr.concat(@filters)

      return arr unless shallow?
      return arr unless parent = @parent

      parent.collect_filters(arr)
    end

    @__acc = [] of Filter

    # Collects and yields applicable filters.
    #
    # Please please do not nest for the same container. This will
    # break everything.
    private def each_filter(& : Filter ->)
      @__acc.clear

      collect_filters(@__acc).each do |filter|
        yield filter
      end
    end

    # Applies filters. Warns the user of rejected runnables
    # if necessary.
    private def apply_filters!
      @runnables.select! do |runnable|
        status = true
        each_filter do |filter|
          next if filter.call(runnable)
          if filter.warn
            @root.ignored(runnable)
          end
          status = false
          break
        end
        status
      end
    end

    def constituents
      shallow? ? @runnables : super
    end

    # Inserts *runnable* after all other runnables in this container.
    def append(runnable : Runnable)
      @runnables << runnable
    end

    # Inserts the entire array of *runnables* after all other runnables
    # in this container.
    def append(runnables : Array(Runnable))
      @runnables.concat(runnables)
    end

    # Inserts *runnable* before all other runnables in this container.
    def prepend(runnable : Runnable)
      @runnables.unshift(runnable)
    end

    # Returns whether this container is empty, i.e., holds
    # has no constituent runnables.
    def empty?
      @runnables.empty?
    end

    # Returns whether this container includes the given *runnable*.
    def includes?(other)
      @runnables.includes?(other)
    end

    # Yields constituent runnables.
    def each(& : Runnable ->)
      @runnables.each { |runnable| yield runnable }
    end

    # :nodoc:
    def push_filter(filter : Filter)
      @filters << filter
    end

    # Introduces a *filter* for the constituent runnables of
    # this container. *filter* should decide whether to accept
    # (true) or reject (false) a runnable.
    #
    # *warn* specifies whether the user should be notified if
    # the filter rejects a runnable.
    def allow?(warn = false, &filter : Runnable -> Bool)
      push_filter Filter.new(filter, warn)
    end

    # Returns whether this container's filters allow it to
    # contain the given *runnable*.
    def can_contain?(runnable : Runnable)
      each_filter do |filter|
        return false unless filter.call(runnable)
      end

      true
    end

    # Returns the absolute path to the directory of this container.
    def abspath
      raise "BUG: container dir path is not an absolute path" unless @dir.absolute?

      @dir
    end

    # Returns whether an application `RunnableGroup` is the direct
    # ancestor of this container.
    def app?
      !!@ancestor.as?(RunnableGroup).try &.app?
    end

    # Returns whether a library `RunnableGroup` is the direct
    # ancestor of this container.
    def lib?
      !!@ancestor.as?(RunnableGroup).try &.lib?
    end

    # Creates a `RunnableDir`, `RunnableScript`, or `RunnableSharedObject`
    # depending on what *datum* points to and its extension.
    #
    # *ancestor* is set as the ancestor of the created runnable.
    #
    # Returns nil if *datum* does not exist.
    def classify?(datum : Path, ancestor : Ancestor?) : Runnable?
      return unless presence = @root.disk.info?(datum)

      datum = presence.path

      return RunnableDir.new(datum, ancestor) if presence.info.directory?
      return unless presence.info.file?

      case datum.extension
      when RunnableScript::EXTENSION
        RunnableScript.new(datum, ancestor)
      when RunnableSharedObject::EXTENSION
        RunnableSharedObject.new(datum, ancestor)
      end
    end

    # If *datum* is a capability, creates and returns an appropriate
    # `RunnableCapability` object. Otherwise, tries to convert *datum*
    # to an absoulte, normalized path, and then passes it to the other
    # `classify?(datum : Path, ancestor : Ancestor?)`.
    #
    # Returns nil if neither succeeded.
    def classify?(datum : String, ancestor : Ancestor?) : Runnable?
      return RunnableCapability.new(datum, ancestor) if @root.capability?(datum)

      path = Path[datum]
      unless path.absolute?
        path = @dir / path
        path = path.normalize

        # Being in primary origin means it's safe to escape it. Current
        # working directory is usually the primary origin, so the user
        # will expect `../foo.nk` to work (assuming it exists).
        #
        # Since escaping backup (secondary) origins looks like magic
        # and can lead to security problems if injection is allowed
        # somewhere, we don't allow that. Injection *will* work on
        # the primary origin *by default*. However, it's easier to
        # ensure that doesn't happen, and hundred times easier to
        # notice. With secondary origins on the other hand, you don't
        # even know where they point most of the time.
        return unless @root.in_primary_origin? || @root.belongs_to_origin?(path, secondary: true)
      end

      classify?(path, ancestor)
    end

    # Recursively yields file and directory paths in this container.
    def each_path(fn : Path ->)
      @runnables.each do |runnable|
        if runnable.is_a?(RunnableContainer)
          fn.call(runnable.abspath)
          runnable.each_path(fn)
        elsif runnable.is_a?(RunnableScript) || runnable.is_a?(RunnableGroup)
          fn.call(runnable.abspath)
        end
      end
    end

    # :ditto:
    def each_path(&fn : Path ->)
      each_path(fn)
    end

    # Returns a set of *all* paths (file, directory, etc. paths) in
    # this container, including those in nested containers.
    def paths
      paths = Set(Path).new
      each_path { |path| paths << path }
      paths
    end

    # Yields all paths matching *selector* in lexicographic order.
    # The paths are initially taken from the directory of this
    # container. See `Disk#glob` for details.
    def each_sorted_path(selector : GlobSelector, & : Path ->)
      paths = [] of Path

      @root.disk.glob(@dir, selector) do |path|
        paths << path
      end

      # FIXME: compare() doesn't seem to be lexicographic
      paths.unstable_sort! { |a, b| a.to_s.compare(b.to_s, case_insensitive: true) }
      paths.each do |path|
        yield path
      end
    end

    # Replaces *pattern* runnable with the *replacement* runnable
    # in this container only (i.e., does not recurse).
    def replace(pattern : Runnable, replacement : Runnable)
      return unless can_contain?(replacement)

      @runnables.map! do |runnable|
        pattern == runnable ? replacement : runnable
      end
    end

    # Replaces *pattern* runnable with multiple *replacement* runnables
    # in this container only (i.e. does not recurse). Their order will
    # be the same as in *replacement*.
    #
    # Runnables from *replacement* that this container cannot contain
    # are left out.
    def replace(pattern : Runnable, replacement : Array(Runnable))
      replacement = replacement.select { |runnable| can_contain?(runnable) }

      @runnables = @runnables.flat_map do |runnable|
        pattern == runnable ? replacement : runnable
      end
    end

    # Accepts only those runnable in this container and all nested
    # containers for which *fn* returns true.
    #
    # The rejected runanbles (runnables for which *fn* returned false)
    # are mutably deleted.
    def recursive_select!(fn : Runnable -> Bool)
      @runnables.select! { |runnable| fn.call(runnable) }
      @runnables.each do |runnable|
        next unless runnable.is_a?(RunnableContainer)
        runnable.recursive_select!(fn)
      end
    end

    # :ditto:
    def recursive_select!(&fn : Runnable -> Bool)
      recursive_select!(fn)
    end

    # Replaces all non-terminal (see `Runnable::Terminal`) runnables
    # with the result of *fn*. Recurses into nested containers.
    def recursive_nonterminal_map!(fn : Runnable, RunnableContainer -> Runnable)
      @runnables.map! do |runnable|
        next runnable if runnable.is_a?(Terminal)

        if runnable.is_a?(RunnableContainer)
          runnable.recursive_nonterminal_map!(fn)
          next runnable
        end

        fn.call(runnable, self)
      end

      apply_filters!
    end

    # :ditto:
    def recursive_nonterminal_map!(&fn : Runnable, RunnableContainer -> Runnable)
      recursive_nonterminal_map!(fn)
    end

    # Calls *fn* with each nonterminal and current container, recurses
    # into nested `RunnableContainer`s.
    def recursive_nonterminal_each(fn : Runnable, RunnableContainer ->)
      @runnables.each do |runnable|
        next if runnable.is_a?(Terminal)

        if runnable.is_a?(RunnableContainer)
          runnable.recursive_nonterminal_each(fn)
          next
        end

        fn.call(runnable, self)
      end
    end

    # :ditto:
    def recursive_nonterminal_each(&fn : Runnable, RunnableContainer ->)
      recursive_nonterminal_each(fn)
    end

    # Recursively rewrites wrapped shallow containers to
    # their content.
    def flatten!
      @runnables = @runnables.flat_map do |runnable|
        runnable.flatten! if runnable.is_a?(RunnableContainer)
        runnable.constituents
      end
    end

    # Builds and returns a child of this container.
    #
    # Optionally, the *dir*ectory of the child can be provided.
    # Otherwise, the directory of this container will be used
    # instead.
    #
    # Additionally, you can specify whether the child should
    # be *shallow*.
    #
    # Shallow containers are transparent to filter inheritance:
    # this means that *shallow containers can inherit filters of their
    # parent shallow containers*. Non-shallow containers are opaque
    # to filter inheritance. This means that *shallow containers
    # won't inherit filters of containers above a non-shallow container,
    # and non-shallow containers themselves won't inherit anything
    # from the container(s) above*.
    def child(dir = @dir, shallow = false)
      RunnableContainer.new(@root, dir, parent: self, shallow: shallow)
    end

    # Builds and returns the `ResolutionSet` with resolutions from
    # this container and all nested containers.
    #
    # You must call this after `flatten!`. Otherwise, the resulting
    # `ResolutionSet` will be underpopulated with dependencies due
    # to shallow containers obstructing the way.
    #
    # *inherit* is a set of dependencies that *all* resolutions should
    # have, regardless of nesting.
    def to_resolution_set(inherit = Set(Resolution::Dependency).new)
      set = ResolutionSet.new

      # All resolutions under this container will inherit the
      # following dependencies.
      deps = inherit.concat(@runnables.select(Resolution::Dependency).to_set)

      @runnables.each do |runnable|
        case runnable
        when RunnableContainer
          resolution = runnable.to_resolution_set(deps.dup)
        when RunnableScript
          resolution = Resolution.new(runnable, deps: deps.dup)
        else
          next
        end

        set.append(resolution)
      end

      set
    end

    # Rewrites this container until there is no point in doing so.
    # That is, until `R` (current) and `R'` (rewritten) are equal:
    # `R = R'`.
    #
    # Quite obviously this method is susceptible to cyclic expansion
    # when the length of the cycle is higher than, well, zero
    # (e.g. `R -> R' -> R -> ...`). So please don't do that nor
    # cause that!
    def rewrite
      @root.down(caller: @ancestor.as?(Runnable) || self)

      loop do
        previous = @runnables

        @runnables = [] of Runnable

        # Specialize previous generation of runnables into a new
        # generation, populating this container.
        previous.each &.specialize(@root, container: self)

        # Leave only those runnables in the new generation of
        # runnables that pass all filters.
        apply_filters!

        break if previous == @runnables
      end
    ensure
      @root.up
    end

    def specialize(root : RunnableRoot, container : RunnableContainer)
      return if empty?

      rewrite

      container.append(self)
    end

    def to_s(io, indent = 0, lead = indent)
      io << " " * lead
      io << "Shallow" if shallow?
      io << "Container[" << @dir << "#" << object_id << "]:\n"

      indent += 2

      @runnables.join(io, '\n') do |runnable|
        if runnable.is_a?(RunnableContainer)
          runnable.to_s(io, indent: indent)
        else
          io << " " * indent << runnable
        end
      end
    end
  end

  # Runnable root is available to all containers, and therefore
  # allows to escape deep nesting if need be. It also holds the
  # list of origins in order to perform an *thorough rewrite* -
  # a rewrite after which it is truly unnecessary to rewrite
  # again, assuming the list of origins hasn't changed.
  #
  # Runnable root also stores a pointer to the `Disk` object,
  # used throughout the system to cache file system requests
  # (the system is quite ample in issuing them).
  class RunnableRoot
    # Returns the disk used by this runnable root.
    getter disk

    def initialize(@caps : CapabilityCollection, @disk : Disk, @ignored : Runnable ->)
      @flags = Set(String).new
      @origins = [] of Path
      @queries = [] of RunnableQuery
      @committing = false
    end

    # :nodoc:
    def ignored(runnable : Runnable)
      @ignored.call(runnable)
    end

    # Assigns *state* to a boolean flag with the given *name*.
    #
    # Note that by design, an unset flag is a false flag, and
    # vice versa: if *state* is false, the flag is either not
    # created, or removed.
    #
    # ```
    # root.set_flag("happy", true)
    # root.set_flag("sad", false)
    # ```
    def set_flag(name : String, state : Bool)
      if state
        @flags << name
        return
      end

      # If flag was on but is now set to off, remove it from
      # the flags set.
      if name.in?(@flags)
        @flags.delete(name)
      end
    end

    # Yields all *true* flags.
    def each_true_flag(& : String ->)
      @flags.each { |flag| yield flag }
    end

    # Returns whether *datum* is a capability.
    def capability?(datum : String)
      @caps.has_capability?(datum)
    end

    @depth = 0

    # :nodoc:
    def down(caller)
      if @depth > RESOLVER_RECURSION_LIMIT
        raise ResolverError.new("recursion depth exceeded: maybe there is a dependency cycle?", caller)
      end

      @depth += 1
    end

    # :nodoc:
    def up
      @depth -= 1
    end

    # Pushes a *query* to the list of queries to-be-resolved during
    # a `commit`. Returns the `RunnableQuery` object.
    #
    # You cannot push a query during a `commit`.
    def push_query(query : Query) : RunnableQuery
      if @committing
        raise "BUG: cannot push new queries during a commit"
      end

      RunnableQuery.new(query).tap { |obj| @queries.push(obj) }
    end

    # Pushes an *origin* path to the list of origin paths maintained
    # by this runnable root.
    #
    # You cannot push an origin during a `commit`.
    #
    # Origin paths are alternate lookup paths. If no prior origin paths,
    # *origin* is *the* lookup path. Origins are explored one after
    # another, in insertion (push) order.
    #
    # To *explore* an origin means to rewrite the runnable tree completely
    # (i.e. until it can no longer be rewritten) using this origin.
    #
    # Naturally, in the beginning, your runnable tree is populated mainly
    # by queries. Most of them are probably going to be rewritten to scripts
    # in the first (primary) origin.
    #
    # With progress through the origin list, the amount of unresolved queries
    # will reduce. After all origins were exhausted, the only remaining non-
    # terminal runnables are going to be the so-called "unknowns", i.e.,
    # queries apparently unrelated to Novika, perhaps typos or something else.
    def push_origin(origin : Path)
      if @committing
        raise "BUG: cannot push new origin during a commit"
      end

      return if origin.in?(@origins)

      @origins.push(origin)
    end

    # Yields origin paths maintained by this runnable root.
    def each_origin(& : Path ->)
      @origins.each { |origin| yield origin }
    end

    @in_primary_origin = false

    # Returns whether this runnable root is currently rewriting
    # using the primary origin.
    #
    # This method must be called during a `commit`.
    def in_primary_origin? : Bool
      unless @committing
        raise "BUG: cannot call in_primary_origin? outside of commit"
      end

      @in_primary_origin
    end

    # Returns whether *path* belongs to one of the origins
    # registered in this runnable root.
    def belongs_to_origin?(path : Path, secondary = false) : Bool
      each_origin do |origin|
        if secondary
          secondary = false
          next
        end

        return true if path == origin

        path.each_parent do |parent|
          return true if parent == origin
        end
      end

      false
    end

    # Thoroughly rewrites the given *base* runnable container. See
    # `push_origin` for detailed information on the rewrite order etc.
    #
    # Mainly for internal use, deep (very deep!) recursions and
    # neck breaking leaps of faith.
    def thorough_rewrite(base : RunnableContainer)
      return if @origins.empty?

      @in_primary_origin = true

      # Perform the first rewrite. This will take care of the
      # easy stuff.
      base.rewrite

      @in_primary_origin = false

      # List of containers we'll skip because they're in a nested/
      # inner env, so shouldn't be affected by global origins.
      skiplist = Set(RunnableContainer).new

      # Try to rewrite containers in their respective environments too
      # (their local origins), assuming they have ones.
      base.recursive_nonterminal_each do |nonterminal, container|
        next unless env = @disk.env?(container.abspath)
        next if env.in?(@origins)

        @origins << env

        begin
          child = container.child(env, shallow: true)
          child.append(nonterminal)
          child.rewrite
        ensure
          unless @origins.delete(env)
            raise "BUG: I added env but could not remove it; consistency lost"
          end
        end

        skiplist << container

        container.replace(nonterminal, child.constituents)
      end

      base.rewrite

      # If that still leaves some unresolved queries, try to
      # rewrite using global origins.
      each_origin do |origin|
        base.recursive_nonterminal_map! do |nonterminal, container|
          next nonterminal if container.in?(skiplist)

          child = container.child(origin, shallow: true)
          child.append(nonterminal)
          child.rewrite

          child
        end

        base.rewrite
      end
    end

    # Constructs a container from the list of queries (see `push_query`),
    # rewrites it until there is no point in rewriting further (performing
    # an *thorough rewrite*), and yields the resulting container.
    #
    # The list of queries is cleared after the commit.
    #
    # Note that it is forbidden to `push_origin` and `push_query` during
    # a commit (i.e., within the block).
    def commit(&)
      return if @origins.empty?

      @committing = true

      primary = RunnableContainer.new(self, @origins[0])

      @queries.each do |query|
        primary.append(query)
      end

      @queries.clear

      thorough_rewrite(primary)

      yield primary
    ensure
      @committing = false
    end
  end
end

module Novika
  class RunnableResolver
    include Resolver

    getter accepted = [] of ResolutionSet
    getter rejected = [] of Runnable
    getter ignored = [] of Runnable

    @env : Path?

    def initialize(caps : CapabilityCollection, @cwd : Path)
      @disk = Disk.new
      @root = RunnableRoot.new(caps, @disk, ->(runnable : Runnable) { @ignored << runnable })
      @env = @disk.env?(cwd)

      # Current working directory is the primary origin. We'll
      # search there first.
      @root.push_origin(cwd)

      # If we found an environment directory, we'll search there
      # later, in case there's no match in cwd.
      @env.try do |env|
        @root.push_origin(env)
      end

      # Set flags for OS etc. Only true stuff is stored internally,
      # so don't worry about the mutual exclusivity of all (or most)
      # of these.
      @root.set_flag("bsd", {{ flag?(:bsd) }})
      @root.set_flag("darwin", {{ flag?(:darwin) }})
      @root.set_flag("dragonfly", {{ flag?(:dragonfly) }})
      @root.set_flag("freebsd", {{ flag?(:freebsd) }})
      @root.set_flag("linux", {{ flag?(:linux) }})
      @root.set_flag("netbsd", {{ flag?(:netbsd) }})
      @root.set_flag("openbsd", {{ flag?(:openbsd) }})
      @root.set_flag("unix", {{ flag?(:unix) }})
      @root.set_flag("windows", {{ flag?(:windows) }})
    end

    private def submit(&)
      @root.commit do |container|
        container.flatten!

        nonterminals = Set(Runnable).new
        container.recursive_nonterminal_each do |nonterminal|
          nonterminals << nonterminal
        end

        yield container.to_resolution_set, nonterminals
      end
    end

    private def to_resolution_set?(query : Query)
      qobj = @root.push_query(query)

      submit do |set, nonterminals|
        # If the same query object is still in the list of nonterminals,
        # then it wasn't rewritten. Therefore, autoloading failed.
        unless nonterminals.empty?
          nonterminals.each do |nonterminal|
            @rejected << nonterminal
          end
          return nil, qobj
        end
        return set, qobj
      end

      {nil, nil}
    end

    def in_env(path : Path, &)
      @env.try { |env| yield path.expand(env) }
    end

    def expand_in_env?(path : Path)
      in_env(path) do |envpath|
        return @disk.file?(envpath)
      end
    end

    def expand_in_cwd?(path : Path)
      @disk.file?(path.expand(@cwd))
    end

    def expand?(path : Path)
      expand_in_cwd?(path) || expand_in_env?(path)
    end

    def autoload_env?
      return nil, nil unless env = @env

      to_resolution_set?(env / "core")
    end

    def autoload_cwd?
      # Try to autoload core in cwd if cwd is an app
      # or a lib.
      return nil, nil if Manifest.find(@disk, @cwd).is_a?(Manifest::Absent)

      to_resolution_set?(@cwd)
    end

    def from_query?(query : String)
      @root.push_query(query)

      submit do |set, nonterminals|
        unless nonterminals.empty?
          nonterminals.each do |nonterminal|
            @rejected << nonterminal
          end
          return false
        end
        @accepted << set
      end

      true
    end

    def from_queries(queries : Array(String))
      qobjs = queries.map { |query| @root.push_query(query) }

      submit do |set, nonterminals|
        unless nonterminals.empty?
          nonterminals.each do |nonterminal|
            @rejected << nonterminal
          end
          return qobjs
        end

        @accepted << set
      end

      qobjs
    end

    def to_s(io)
      origins = [] of Path
      @root.each_origin do |origin|
        origins << origin
      end

      io << "("
      origins.join(io, " | ")
      io << ")"
    end
  end

  # Permission server allows to prompt the user for permissions, and
  # save the user's choices in the *permissions file*.
  #
  # Note that you have to manually call `load` and `save` when
  # appropriate in order to load permissions from disk, and save
  # them on disk for better user experience.
  class PermissionServer
    include Resolver

    # Creates a new permission server.
    #
    # *resolver* is the resolver with which this server will talk about
    # resolver-related things.
    #
    # *explicit* is the list of explicit runnable queries. An explicit
    # query is that query which was specified manually, e.g. via the
    # arguments. In other words, the user had to *type them in* here
    # and now rather than receive them from manifest or whatnot. The
    # explicit query list is mainly used to be less annoying when it
    # comes to asking for permissions.
    def initialize(
      @caps : CapabilityCollection,
      @resolver : RunnableResolver,
      @explicit : Array(RunnableQuery)
    )
      @permissions = {} of Resolution::Dependency::Signature => Permission
    end

    # Fills the permissions hash with saved permissions.
    def load
      return unless saved = @resolver.expand_in_env?(Path[PERMISSIONS_FILENAME])

      csv = CSV.new File.read(saved)
      csv.each do |(dependent, dependency, state)|
        next unless id = state.to_i?
        next unless permission = Permission.from_value?(id)

        @permissions[{dependent, dependency}] = permission
      end
    end

    # Flushes the internal permissions store to disk. Can create the
    # permissions file, if necessary.
    #
    # Note: this method does nothing in case the internal permissions
    # store is empty.
    def save
      return if @permissions.empty?

      @resolver.in_env(Path[PERMISSIONS_FILENAME]) do |savefile|
        csv = CSV.build do |builder|
          @permissions.each do |(dependent, dependency), permission|
            # Do not save undecided / denied because such decision
            # is going to be hard to undo, and could have been made
            # by mistake anyway.
            next if permission.undecided? || permission.denied?

            builder.row(dependent, dependency, permission.to_i)
          end
        end

        File.write(savefile, csv)
      end
    end

    # Tersely describes the purpose of *dependency*.
    def brief(dependency : RunnableCapability) : String
      dependency.purpose(in: @caps)
    end

    # Asks user a *question*, and returns the answer or an empty
    # string in case EOF was received.
    def ask?(question : String) : String?
      print question, " "
      gets
    end

    # Prints *answer* so that it can be seen by the user.
    def answer(answer : String)
      print answer
    end

    # Returns whether *dependency* is explicit.
    #
    # This is done by checking whether the *first* `RunnableQuery`
    # ancestor of *dependency* is in the explicit list. See `new`
    # to learn what "explicitness" means.
    def explicit?(dependency : Resolution::Dependency) : Bool
      dependency.each_ancestor do |ancestor|
        next unless ancestor.is_a?(RunnableQuery)
        return @explicit.any?(ancestor)
      end

      false
    end

    # Queries (possibly prompts) and returns the permission state of
    # *dependency* for the given *group*.
    def query_permission?(group : RunnableGroup, dependency : Resolution::Dependency)
      @permissions[dependency.signature(group)] ||= dependency.prompt?(self, for: group)
    end

    # Requests *dependency* for the given set of *dependents*.
    #
    # This process happens in two steps.
    #
    # First, we determine whether the user allows the use of
    # *dependency* in groups from *dependents* (this is done by
    # asking the user or reading the saved permissions file).
    #
    # The decision is also saved in the permissions file *if it
    # was positive*.
    #
    # Note that you still have to explicitly enable depenendencies
    # using `Resolution::Dependency#enable`. Dependencies that weren't
    # allowed are simply going to refuse enabling themselves.
    def request(dependency : Resolution::Dependency, for dependents : ResolutionSet)
      skiplist = Set(Resolution).new
      visited = Set(RunnableGroup).new

      # Go through apps and libs, add their resolutions to the skiplist.
      # React only to never-seen-before groups.
      dependents.each_group do |group, resolution|
        next unless group.app? || group.lib?

        if group.in?(visited)
          skiplist << resolution
          next
        end

        dependency.request(self, for: group)

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
  end
end
