require "csv"

module Dir::Globber
  # I guess the thing is private for a reason, but I need it anyway!!1

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

  # Base class of signals received by `SignalReceiver`s
  abstract struct Signal
  end

  # Asks signal receivers to load whatever data they can
  # (and should) from disk.
  struct DoDiskLoad < Signal
  end

  # Asks signal receivers to save whatever data they can
  # (and should) to disk.
  struct DoDiskSave < Signal
  end

  # Lets signal receivers acknowledge that a runnable was ignored.
  record RunnableIgnored < Signal, runnable : Runnable

  # If signal receivers want to ask a question, gives them
  # a Proc which will do that and return a string answer, or
  # nil if the user discarded the question.
  struct ToAskDo < Signal
    alias Fn = String -> String?

    # Returns the proc which should be used to ask a question.
    getter fn

    def initialize(@fn : Fn)
    end
  end

  # If signal receivers want to answer a question, gives them
  # a Proc which will allow them to do that.
  struct ToAnswerDo < Signal
    alias Fn = String ->

    # Returns the proc which should be used to answer a question.
    getter fn

    def initialize(@fn : Fn)
    end
  end

  # `SignalReceiver`s can receive signals sent by the `RunnableRoot`.
  #
  # This is basically an observer/observable system sitting on top of
  # runnable root, mainly to have a nice way to communicate, via runnable
  # root, with objects interested in communication.
  module SignalReceiver
    # Receives and reacts to a *signal* sent by `RunnableRoot`.
    abstract def receive(signal : Signal)
  end

  # Base class for resolver and resolver-related exceptions.
  class ResolverError < Exception
  end

  # Raised when there is an error during runnable resolution.
  class RunnableError < ResolverError
    # Returns the runnable which is assumed to be the source of
    # this error.
    getter runnable

    def initialize(@message, @runnable : Runnable)
    end
  end

  # Raised when there are rejected runnables in a response.
  class ResponseRejectedError < ResolverError
    # Returns the response which contains some rejected runnables.
    getter response

    def initialize(@response : Response)
      @message = "could not resolve runnable"
    end
  end

  # Raised when the user tries to run more than one app.
  class MoreThanOneAppError < ResolverError
    # Returns the array of apps in the response; more than of
    # them there.
    getter apps

    def initialize(@apps : Array(RunnableGroup))
      @message = "could not determine which one of the apps to run"
    end
  end

  # A caching, resolver-specific file system access abstraction on top
  # of Crystal's `Dir` and `File`.
  class Disk
    # Represents the presence of the requested file system entry
    # (directory, file, or symlink) at `path`. Also holds its
    # `File::Info` object, `info`.
    #
    # See `info?`.
    record InfoPresence, path : Path, info : File::Info

    # Represents the absence of the requested file system entry.
    #
    # No need to instantiate; use `InfoAbsent`.
    #
    # See `info?`.
    record InfoAbsence

    # Singleton instance of `InfoAbsence`.
    InfoAbsent = InfoAbsence.new

    def initialize
      # Records presence/absence of file info for path.
      @info = {} of Path => InfoPresence | InfoAbsence

      # Records presence/absence of an environment directory for path.
      # Paths that were climbed to find the environment directory are
      # also here, pointing to the latter (or to the absence of latter).
      @envs = {} of Path => Path?

      # Directory paths mapped to their glob-able content.
      @globs = {} of Path => Array(GlobEntry)

      # Path mapped to file content, to save on reading frequently/
      # repeatedly accessed files etc.
      @content = {} of Path => String
    end

    # Reads, caches, and returns the `InfoPresence` object for the
    # given *path*. Returns nil if there is nothing at *path*. The
    # absence is also cached.
    #
    # *path* is assumed to be absolute and normalized.
    #
    # If *path* is a symlink, the symlink is visited. Therefore, the
    # returned `InfoPresence` will contain the real path rather than
    # *path*. So prefer to use the resulting `InfoPresence#path` in
    # favor of *path* after calling this method.
    def info?(path : Path) : InfoPresence?
      presence = nil

      if presence = @info[path]?
        return presence.as?(InfoPresence)
      end

      # If the entry is absent, cache & and bail out.
      unless info = File.info?(path, follow_symlinks: false)
        @info[path] = InfoAbsent
        return
      end

      # If the entry exists and isn't a symlink, cache & bail out.
      unless info.symlink?
        return @info[path] = InfoPresence.new(path, info)
      end

      # If the entry exists but is a symlink, try again but with
      # its real path.
      real = Path[File.realpath(path)]
      info = File.info?(real, follow_symlinks: false)
      presence = info ? InfoPresence.new(real, info) : InfoAbsent

      # Cache both for real and symlink paths, so that we won't
      # have to realpath again.
      @info[real] = presence
      @info[path] = presence

      presence.as?(InfoPresence)
    end

    # If *path* (symlink or not) points to a file, returns the real
    # path to that file. Otherwise, returns nil.
    def file?(path : Path) : Path?
      return unless presence = info?(path)
      return unless presence.info.file?

      presence.path
    end

    # If *path* (symlink or not) points to a directory, returns the
    # real path to that directory. Otherwise, returns nil.
    def dir?(path : Path) : Path?
      return unless presence = info?(path)
      return unless presence.info.directory?

      presence.path
    end

    # Returns the content of the file that *path* points to.
    #
    # Raises if *path* doesn't point to a file.
    def read(path : Path) : String?
      @content[path] ||= File.read(path)
    end

    # Yields writable `IO` for the file that *path* points to. The
    # file is created if it does not exist; its content is cleared
    # if it does.
    def write(path : Path, & : IO ->)
      File.open(path, mode: "w") do |io|
        yield io
      end
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
    #
    # The result is cached, recursively, so you can call this method
    # as many times as you'd like; your disk won't explode.
    def env?(origin : Path) : Path?
      env : Path?

      return env if env = @envs[origin]?

      return @envs[origin] = origin if file?(origin / ENV_LOCAL_PROOF_FILENAME)
      return @envs[origin] = env if env = dir?(origin / ENV_GLOBAL_DIRNAME)
      return @envs[origin] = env if (env = dir?(origin / ENV_LOCAL_DIRNAME)) && file?(env / ENV_LOCAL_PROOF_FILENAME)

      if origin == origin.root && (env = dir?(Path.home / ENV_GLOBAL_DIRNAME))
        # Check one more time, maybe env is in home and we're coming
        # from a different drive?
        return @envs[origin] = env
      end

      return unless env = env?(origin.parent)

      @envs[origin] = env
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

        def prompt?(server : PermissionServer, *, for container : RunnableContainer) : Permission
          label = label(server)

          prompt = String.build do |io|
            io << "Allow " << container.abspath << " to load " << label
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
      #
      # *container*, assumed to contain this dependency, may be used
      # to derive the signature.
      abstract def signature(container : RunnableContainer) : Signature

      # If this dependency is `allowed?`, enables it in the given
      # capability collection *caps*.
      abstract def enable(*, in caps : CapabilityCollection)

      # Promps the user for whether the use of this dependency should
      # be allowed in *container*'s `RunnableEnvironment`. Returns the
      # resulting `Permission`.
      abstract def prompt?(server : PermissionServer, *, for container : RunnableContainer) : Permission

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

      # Communicates with the given permission *server* in order to
      # determine whether the use of this dependency should be allowed
      # to *container*.
      def request(server : PermissionServer, *, for container : RunnableContainer)
        return unless @permission.undecided?

        # Ask the server if this dependency is explicit. A dependency
        # is considered explicit when it is specified in the arguments
        # by hand.
        if server.explicit?(self)
          @permission = Permission::Allowed
          return
        end

        @permission = server.query_permission?(container, self)
      end
    end

    # Returns the absolute path to this resolution.
    getter abspath : Path

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

    # Opens an instance of *script block* (aka *file block*) with *engine*.
    #
    # Extends *script block* itself with `__path__`, `__file__`; therefore,
    # mutates *script block*.
    #
    # Returns the script block instance after evaluation.
    def run(engine : Engine, script_block : Block) : Block
      script_block.at(Word.new("__path__"), Quote.new(@abspath.parent.to_s))
      script_block.at(Word.new("__file__"), Quote.new(@abspath.to_s))

      instance = script_block.instance
      instance.schedule!(engine, stack: Block.new)

      engine.exhaust

      instance
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

    # Returns an array of unique application `RunnableGroup`s that
    # have contributed to this resolution set.
    def unique_apps : Array(RunnableGroup)
      unique_apps = [] of RunnableGroup
      each_unique_app do |app|
        unique_apps << app
      end
      unique_apps
    end

    # Yields library `RunnableGroup`s that have contributed
    # to this resolution set.
    def each_unique_lib(& : RunnableGroup ->)
      each_unique_group do |group|
        next unless group.lib?
        yield group
      end
    end

    # Yields all unique `Resolution::Dependency` objects in
    # this resolution set.
    def each_unique_dependency(& : Resolution::Dependency ->)
      visited = Set(Resolution::Dependency).new

      each do |resolution|
        resolution.each_dependency do |dependency|
          next if dependency.in?(visited)
          yield dependency
          visited << dependency
        end
      end
    end

    # Yields each unique `Resolution::Dependency` object followed
    # by a `ResolutionSet` of its dependents.
    def each_unique_dependency_with_dependents(& : Resolution::Dependency, ResolutionSet ->)
      map = {} of Resolution::Dependency => ResolutionSet

      each do |resolution|
        resolution.each_dependency do |dependency|
          set = map[dependency] ||= ResolutionSet.new
          set.append(resolution)
        end
      end

      map.each { |dependency, set| yield dependency, set }
    end

    # Yields environment designations for the given runnable *root*.
    #
    # *Environment designations* are resolution sets coupled to an
    # environment. That is, an environment designation is a "token"
    # stating *this* environment should handle resolutions out of
    # *that* resolution set.
    def each_designation(root : RunnableRoot, & : Designation ->)
      visited = Set(Resolution).new
      designations = {} of RunnableEnvironment => ResolutionSet

      each_group do |group, resolution|
        next if resolution.in?(visited)
        next unless container = root.containerof?(group)

        set = designations[container.@env] ||= ResolutionSet.new
        set.append(resolution)

        visited << resolution
      end

      default = designations[root.default_env] ||= ResolutionSet.new

      each do |resolution|
        next if resolution.in?(visited)

        default.append(resolution)
      end

      designations.each do |env, set|
        yield env.designate(set)
      end
    end

    # Yields preambles of unique application and library `RunnableGroup`s
    # that have contributed to this resolution set, as well as the
    # groups themselves.
    def each_preamble_with_group(root : RunnableRoot, & : String, RunnableGroup ->)
      each_unique_group do |group|
        next unless group.app? || group.lib?
        next unless preamble = root.preambleof?(group)
        yield preamble, group
      end
    end

    def to_s(io)
      io.puts("ResolutionSet")

      each do |resolution|
        io << " | " << resolution
        io.puts
      end
    end
  end

  # Designation objects encapsulate a runnable environment and a
  # set of resolutions that should be run within that environment.
  #
  # The preferred way to create designations is via `RunnableEnvironment#designate`.
  #
  # After obtaining a designation, you can `run` it as many times
  # as you want.
  struct Designation
    getter caps

    def initialize(
      @root : RunnableRoot,
      @env : RunnableEnvironment,
      @set : ResolutionSet,
      @caps : CapabilityCollection
    )
      @set.each_unique_dependency &.enable(in: @caps)
    end

    # Fills *block* with unambiguous preamble mappings.
    private def fill_preambles_block(block : Block)
      names = {} of String => RunnableGroup
      preambles = {} of RunnableGroup => String
      conflicts = Set({RunnableGroup, RunnableGroup}).new

      @set.each_preamble_with_group(@root) do |preamble, group|
        preambles[group] = preamble

        # If there's a group with the same name already, remove it from
        # "names" and add the pair of conflicting groups to "conflicts".
        if existing = names[group.name]?
          names.delete(group.name)
          conflicts << {group, existing}
          next
        end

        names[group.name] = group
      end

      a_disamb = [] of String
      b_disamb = [] of String

      # Resolve conflicts by starting with the name, then trying to
      # add more path terms in reverse before the conflict goes away.
      #
      #    foo        xyz/foo        a/xyz/foo
      #          >>>           >>>               >>> CONFLICT RESOLVED
      #    foo        xyz/foo        b/xyz/foo
      conflicts.each do |(a, b)|
        ap = a.abspath.parts
        bp = b.abspath.parts

        # Let's just hope that a and b are different!
        loop do
          l = ap.pop?
          r = bp.pop?
          a_disamb.unshift(l) if l
          b_disamb.unshift(r) if r
          break unless l == r
        end

        names[a_disamb.join('/')] = a
        names[b_disamb.join('/')] = b

        a_disamb.clear
        b_disamb.clear
      end

      names.each do |name, group|
        block.at(Word.new(name), Quote.new(preambles[group]))
      end
    end

    # Returns the label of this designation, which is formed from
    # the basename of this designation's runnable environment.
    def label : String
      @env.abspath?.try(&.basename) || "unknown"
    end

    # Parses the designated resolutions and appends the parsed forms to
    # *target*. Their order is kept, and matches that of the corresponding
    # resolution in this designation's resolution set.
    def slurp(target : Block)
      preambles = target.form_for?(Word.new("__preambles__")).as?(Block)
      preambles ||= Block.new
      fill_preambles_block(preambles)

      target.at(Word.new("__preambles__"), preambles)

      @set.each do |resolution|
        source = @root.disk.read(resolution.abspath)
        script = Block.new(target).slurp(source)
        target.paste(script)
      end
    end

    # Runs the designated resolutions under a new common toplevel block.
    def run
      preambles = Block.new
      fill_preambles_block(preambles)

      # Important: wrap capability block in another block! This is
      # required to make it possible to ignore capability block in
      # Image emission, saving some time and space!
      toplevel = Block.new(@caps.block)
      toplevel.at(Word.new("__runtime__"), Quote.new("novika"))
      toplevel.at(Word.new("__preambles__"), preambles)

      engine = Engine.push(@caps)

      @set.each do |resolution|
        source = @root.disk.read(resolution.abspath)
        script = Block.new(toplevel).slurp(source)
        instance = resolution.run(engine, script_block: script)
        toplevel.import!(from: instance)
      end

      Engine.pop(engine)
    end

    def to_s(io, sm = false)
      envpath = @env.abspath?

      if sm && envpath
        @set.each do |resolution|
          io.puts(resolution.abspath.relative_to?(envpath) || resolution.abspath)
        end

        return
      end

      envpath ||= "unknown"

      io << envpath << ": [\n"

      @set.each do |resolution|
        io << "  " << resolution.abspath << ",\n"
      end

      io << "]\n"
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

      # Returns whether the datum of this runnable is equal to *other*.
      def ==(other : T)
        @datum == other
      end

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

    # Returns an array of ancestors of this runnable, starting from
    # the most recent ancestor and ending with the oldest one.
    def ancestors : Array(Ancestor)
      ancestors = [] of Ancestor
      each_ancestor do |ancestor|
        ancestors << ancestor
      end
      ancestors
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
      backtrace = ancestors.reverse
      backtrace << self

      io << "  ┬\n"

      ws = " " * indent
      backtrace.each do |runnable|
        io << ws << "╿ in "
        if runnable.is_a?(RunnableContainer)
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

    def signature(container : RunnableContainer) : Signature
      {container.abspath.to_s, @datum}
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

    def signature(container : RunnableContainer) : Signature
      {container.abspath.to_s, @datum.to_s}
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

    # Replaces any occurences of this slot in *container* with a
    # container holding the runnables this slot stands for.
    #
    # *manifest* is the manifest that contains this slot.
    #
    # *group* is the `RunnableGroup` of the manifest that contains
    # this slot.
    #
    # Returns the next population container.
    abstract def replace(
      root : RunnableRoot,
      group : RunnableGroup,
      manifest : Manifest::Present,
      population : RunnableContainer,
      container : RunnableContainer
    ) : RunnableContainer
  end

  # Slot (placeholder) that stands for "all not otherwise mentioned
  # Novika scripts" in the container's directory, represented with `**`.
  class ScriptsSlot < Slot
    def replace(
      root : RunnableRoot,
      group : RunnableGroup,
      manifest : Manifest::Present,
      population : RunnableContainer,
      container : RunnableContainer
    ) : RunnableContainer
      mentioned = population.paths

      # Fill a transparent container with Novika scripts from the
      # directory where the manifest is located.
      content = container.child(manifest.directory, transparent: true, ancestor: self)

      root.disk.glob(manifest.directory, GlobSelector::Scripts) do |datum|
        next if datum.in?(mentioned)

        content.append RunnableScript.new(datum, ancestor: self)
      end

      container.replace(self, content)

      population
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
      population : RunnableContainer,
      container : RunnableContainer
    ) : RunnableContainer
      mentioned = population.paths

      # Note that we ignore apps and libs. This is necessary due to
      # the use of `layout`, as it is unaware that we only want to
      # match manifest-absent directories (and it will match any).
      #
      # Now, an outer app/lib will be rejected, henceforth rejecting
      # all nested ones. Note also, that transparent containers inherit
      # filters of the transparent containers above, up to and including
      # the first opaque one. As opaque containers appear only in manifests
      # (and groups that are the source of them we've rejected already),
      # the filter below is supposed to have no breaches.
      content = container.child(manifest.directory, transparent: true, ancestor: self)
      content.allow? { |r| !(r.is_a?(RunnableGroup) && (r.app? || r.lib?)) }

      container.replace(self, content)

      manifest.layout(content, group)

      # We don't need a thorough rewrite here because `layout` is file
      # system-only, and all files in the file system exist by definition --
      # and therefore it won't leave any "unanwsered" queries.
      content.rewrite

      # Leave only containers, and optionally those scripts that weren't
      # already mentioned (incl. by the scripts slot, which has higher
      # precedence and is therefore expanded before the subtree slot).
      content.recursive_select! do |runnable|
        unless runnable.is_a?(RunnableScript) || runnable.is_a?(RunnableContainer)
          next false
        end

        !runnable.abspath.in?(mentioned)
      end

      population
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
      population : RunnableContainer,
      container : RunnableContainer
    ) : RunnableContainer
      # Create an empty container, allow everything in it -- make
      # it opaque to filter inheritance.
      content = population.child(transparent: false, ancestor: self)

      # Replace myself with the container.
      container.replace(self, content)

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
    # Base class for several *subtractive preprocessors* for
    # manifest content.
    #
    # They are *subtractive* because they *discard* stuff, at
    # least from the original content's point of view.
    #
    # Also, one might say *subtractive preprocessors* match "edges"
    # rather than by "structure". If done repeatedly and so to speak
    # recursively, one might finally arrive at "grains" coarse enough
    # for "real" content analysis. In this sense subtractive
    # preprocessors are "noise-friendly" -- and that's just what we
    # want. Moreover, they may consider each other "noise", too.
    #
    # Preprocessors can be chained, and can programmaticaly select
    # the next preprocessor (or become the terminal one) in `next?`.
    class Preprocessor
      def initialize(
        @root : RunnableRoot,
        @group : RunnableGroup,
        @manifest : Manifest::Present
      )
      end

      # Returns subtractively preprocessed *content* string. That
      # is, the returned string will be shorter or of the same
      # length as *content*.
      def preprocess(content : String) : String
        content
      end

      # Returns the next preprocessor in the chain, or nil if
      # this preprocessor is terminal.
      def next? : Preprocessor?
        PreamblePreprocessor.new(@root, @group, @manifest)
      end
    end

    # Strips off manifest preamble and makes the manifest acknowledge it.
    class PreamblePreprocessor < Preprocessor
      def preprocess(content : String) : String
        # Find first line that consists of '---' only (and maybe some
        # excess whitespace around).
        open = content.match(/^\s*---\s*$/m)

        return content unless open

        # Similarly find the last line. This time though, it may
        # not be there and that's perfectly fine. In this case
        # "postamble" would be a better name, I suppose.
        close = content.match(/^\s*---\s*$/m, pos: open.end)

        range_outer = open.begin...(close ? close.end : content.size)
        range_inner = open.end...(close ? close.begin : content.size)

        preamble = content[range_inner].strip

        @manifest.on_preamble(@root, @group, preamble)

        content.sub(range_outer, "")
      end

      def next? : Preprocessor?
        CommentPreprocessor.new(@root, @group, @manifest)
      end
    end

    # Strips off comments from manifest content.
    class CommentPreprocessor < Preprocessor
      def preprocess(content : String) : String
        content.gsub(/^\s*#[^\n]*/m, "")
      end

      def next? : Preprocessor?
        FlagPreprocessor.new(@root, @group, @manifest)
      end
    end

    # Expands expressions such as `[windows, ... => dll, so]`, if found
    # in manifest content: substitutes each with the appropriate value.
    class FlagPreprocessor < Preprocessor
      def preprocess(content : String) : String
        content.gsub(/\[([^\]]+)\]/) do |exp|
          case $1
          when /^\s*((?:\w|\.\.\.)+(?:\s*,\s*(?:\w|\.\.\.)+)*)\s*\|\s*(\w+(?:\s*,\s*\w+)*)$/
            flags = $1.split(/\s*,\s*/, remove_empty: true)
            blocks = $2.split(/\s*,\s*/, remove_empty: true)
            next exp unless flags.size == blocks.size

            branches = Hash.zip(flags, blocks)
            branch = branches["..."]?

            @root.each_set_flag do |flag|
              next unless block = branches[flag]?
              break branch = block
            end

            branch || ""
          end
        end
      end

      def next? : Preprocessor?
      end
    end

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
      population = container.child(transparent: true, ancestor: origin)
      population.allow? { |r| !(r.is_a?(RunnableGroup) && (r.app? || r.lib?)) }
      container.append(population)

      root.assign(origin, container: population)

      layout(population, origin)
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

    # Invoked when a preamble is found in this manifest. *preamble*
    # is the inner content of the preamble (i.e. without `---`s).
    def on_preamble(
      root : RunnableRoot,
      group : RunnableGroup,
      preamble : String
    )
      root.assign(group, preamble: preamble)
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

    # Returns the preprocessed content of this manifest.
    protected def preprocessed_content(root : RunnableRoot, group : RunnableGroup) : String
      content = root.disk.read(@path)

      preprocessor = Preprocessor.new(root, group, manifest: self)

      while preprocessor = preprocessor.next?
        content = preprocessor.preprocess(content)
      end

      content
    end

    # Processes *fragments* of a manifest: fills *population* with
    # the appropriate runnables.
    #
    # *inherited* stands for whether `self` was inherited. Setting
    # this to `true`  results in more restrictive automatic gathering
    # of files.
    protected def process(
      root : RunnableRoot,
      group : RunnableGroup,
      population : RunnableContainer,
      directives : Array(String),
      fragments : Array(String),
      inherited : Bool
    ) : RunnableContainer
      # Create a container for this manifest specifically. Remember
      # that multiple manifests can contribute to *population* through
      # inheritance, therefore, some bit of separation is necessary.
      container = population.child(directory, transparent: true, ancestor: self)
      container.allow?(warn: true) { |r| !(r.is_a?(RunnableGroup) && r.app?) }

      population.append(container)

      # BUG: if there is a container for group already then we're
      # possibly out of sync.
      root.assign(group, container: container, overwrite: false)

      queries = to_runnables(fragments)
      slots = queries.select(Slot)

      # Populate the manifest container with queries.
      container.append(queries)

      # If no explicit subtree slot, create one & make it so that
      # it is loaded first (this seems to make most sense).
      unless slots.any?(SubtreeSlot) || inherited || directives.includes?("nolayout")
        slot : SubtreeSlot
        slot = SubtreeSlot.new(ancestor: self)
        slots.unshift(slot)
        container.prepend(slot)
      end

      # Perform a thorough rewrite. This guarantees the child
      # *truly* cannot be rewritten any further, regardless of
      # origins etc.
      container.thorough_rewrite

      cons = nil

      slots.each do |slot|
        ingress = slot.replace(root, group, self, population, container)

        next if cons
        next if ingress.same?(population)

        # Set cons to the first "ingress" container different from
        # the population container.
        cons = ingress
      end

      cons || population
    end

    # A set of allowed manifest directives.
    DIRECTIVES = Set{"noinherit", "nolayout"}

    def populate(root : RunnableRoot, container : RunnableContainer, origin : RunnableGroup)
      population = container.child(transparent: false, ancestor: self)
      container.append(population)

      root.assign(origin, container: population)

      # We have to run manifests in grandparent-parent-child-etc. order,
      # but we climb in child-parent-grandparent order and, moreover,
      # child, parent, etc. can interrupt climbing with 'noinherit' or
      # by being of a non-inheritable kind, such as '.nk.app' parent
      # of '.nk.lib'.
      manifests = [] of {Manifest::Present, RunnableGroup, Array(String), Array(String), Bool}

      climb(root, origin) do |manifest, group, isself|
        directives, fragments = manifest.preprocessed_content(root, group)
          .split(/\s+/, remove_empty: true)
          .partition(&.in?(DIRECTIVES))

        manifests << {manifest, group, directives, fragments, !isself}

        break if directives.includes?("noinherit")
      end

      manifests.reverse_each do |manifest, group, directives, fragments, inherited|
        population = manifest.process(root, group, population, directives, fragments, inherited)
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
  #
  # Now to the important bit: since there is never a guaranteed
  # link between a runnable group and the container it was/will
  # be rewritten to, you should manually register it with
  # `RunnableRoot#assign` if you ever want the container to *run*.
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

    # Returns the name of this group.
    def name : String
      @datum.stem
    end

    # Constructs and returns entry filename for this group.
    #
    # For instance, if this group's directory is '/path/to/foo',
    # then its entry filename will be 'foo.nk'.
    def entry_name : String
      "#{name}.nk"
    end

    # Returns an absolute path to this group.
    def abspath
      raise "BUG: group datum is not an absolute path" unless @datum.absolute?

      @datum
    end

    def specialize(root : RunnableRoot, container : RunnableContainer)
      child = container.child(@datum, transparent: true, ancestor: self)
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

  # Represents a Novika environment.
  class RunnableEnvironment
    # Returns the absolute path pointing to this environment's directory.
    getter! abspath

    # Returns the permission server used by this environment.
    private getter! permissions : PermissionServer

    # Returns this environment's personal capability collection.
    #
    # For it to be here is weird but on the other hand, kind of
    # makes sense. For the future-minded, imagine configuring which
    # capabilities are available to runnables in an environment by
    # listing them somehow in '.nk.env'. That could be one of the
    # "whys".
    private getter! capabilities : CapabilityCollection

    def initialize(@root : RunnableRoot, @abspath : Path?)
      @permissions = @root.serve_permissions(to: self)
      @capabilities = CapabilityCollection.with_available.enable_default

      # If the runtime asks for a library that the user didn't specify
      # in the arguments/that wasn't found in system's library directory,
      # we'll try to resolve it in root's working directory and here,
      # in this environment.
      capabilities.on_load_library? do |name|
        Library.new?(name, cwd: @root.cwd, env: self)
      end

      # Wish root to preload my 'core' if I have 'core'; else, the
      # request should be silently ignored.
      if abspath = @abspath
        @root.wish RunnableQuery.new(abspath / "core", else: nil)
      end
    end

    # Expands *datum* in this environment's directory. Returns the
    # resulting real path if *datum* points to something (a file, a
    # directory, etc.); if *datum* points to nothing, returns nil.
    def expand?(datum : Path) : Path?
      return unless abspath = @abspath
      return unless info = @root.disk.info?(abspath.expand(datum))

      info.path
    end

    # Returns whether *datum* is a capability in this environment's
    # capability collection.
    def capability?(datum : String) : Bool
      capabilities.has_capability?(datum)
    end

    # Emits a dependency request (see `Resolution::Dependency#request`)
    # to the permission server of this environment.
    def request(dependency : Resolution::Dependency, for container : RunnableContainer)
      dependency.request(permissions, for: container)
    end

    # Returns the content of the permissions file of this environment
    # followed by its path; or nil if the permissions file does not exist.
    def permissions? : {String, Path}?
      return unless abspath = @abspath
      return unless path = @root.disk.file?(abspath / PERMISSIONS_FILENAME)

      {@root.disk.read(path), path}
    end

    # Yields writable `IO` for the content of this environment's
    # permissions file. Creates one if necessary. Previous content
    # of the file is cleared.
    def permissions(& : IO ->)
      return unless abspath = @abspath

      @root.disk.write(abspath / PERMISSIONS_FILENAME) do |io|
        yield io
      end
    end

    # Creates and returns a `Designation` for this environment to
    # handle the given resolution *set*.
    def designate(set : ResolutionSet) : Designation
      Designation.new(@root, self, set, capabilities.copy)
    end

    # Returns a brief description of *dependency*.
    def brief(dependency : Resolution::Dependency)
      dependency.purpose(in: capabilities)
    end

    # Returns whether *path* is part of this environment's subtree,
    # i.e. is this environment directory's direct or indirect child.
    def includes?(path : Path) : Bool
      return false unless abspath = @abspath
      return true if abspath == path

      path.each_parent do |parent|
        return true if parent == abspath
      end

      false
    end

    # Returns whether *path* points to this environment's directory.
    def ==(path : Path)
      @abspath == path
    end

    # Two environments are equal when their directories are equal.
    def_equals_and_hash @abspath
  end

  # A runnable container is an *ordered*, arbitrarily *filtered*
  # collection of runnables - and a runnable itself.
  class RunnableContainer < Runnable
    # :nodoc:
    record Filter, fn : (Runnable -> Bool), warn : Bool do
      delegate :call, to: fn
    end

    # Returns whether this container is transparent.
    getter? transparent : Bool

    # Initializes a new runnable container for the given *dir*ectory.
    #
    # *parent* is the parent runnable container. You don't normally need
    # to specify it. Prefer to call `child` on the parent instead.
    #
    # *transparent* specifies whether the container is transparent.
    def initialize(
      @root : RunnableRoot,
      @dir : Path,
      @env : RunnableEnvironment,
      @parent : RunnableContainer? = nil,
      @transparent = false,
      ancestor = nil
    )
      super(ancestor)

      @filters = [] of Filter
      @runnables = [] of Runnable
    end

    # Recursively collects filters applicable to this container,
    # starting from this container, to *collection*. Returns *collection*.
    protected def collect_filters(collection : Array(Filter))
      collection.concat(@filters)

      return collection unless transparent?
      return collection unless parent = @parent

      parent.collect_filters(collection)
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
            @root.send RunnableIgnored.new(runnable)
          end
          status = false
          break
        end
        status
      end
    end

    def constituents
      transparent? ? @runnables : super
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

    # Returns whether *env* is this container's environment.
    def from?(env : RunnableEnvironment)
      @env == env
    end

    # Communicates with this container's environment permission
    # server in order to determine whether the use *dependency*
    # should be allowed to `self`.
    def request(dependency : Resolution::Dependency)
      @env.request(dependency, for: self)
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
      return RunnableCapability.new(datum, ancestor) if @env.capability?(datum)

      if datum.starts_with?('^') && (envpath = @env.abspath?)
        path = (envpath / datum.lchop).normalize
        return unless path.in?(@env)
      end

      path ||= Path[datum]
      unless path.absolute?
        path = (@dir / path).normalize

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
        return unless @primary_rewrite || !!path.in?(@env)
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

    # Recursively rewrites wrapped transparent containers to
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
    # be *transparent*.
    #
    # Transparent containers are transparent to filter inheritance:
    # this means that *transparent containers can inherit filters of their
    # parent transparent containers*. Opaque containers are opaque
    # to filter inheritance. This means that *transparent containers
    # won't inherit filters of containers above a opaque container,
    # and opaque containers themselves won't inherit anything
    # from the container(s) above*.
    def child(dir = @dir, ancestor = self, *, transparent : Bool)
      RunnableContainer.new(@root, dir,
        env: @root.defenv(@root.disk.env?(dir)),
        parent: self,
        ancestor: ancestor,
        transparent: transparent,
      )
    end

    # Builds and returns a `ResolutionSet` with resolutions from
    # this container and all nested containers.
    #
    # You must call this after `flatten!`. Otherwise, the resulting
    # `ResolutionSet` will be underpopulated with dependencies due
    # to transparent containers standing in the way.
    #
    # *inherit* is a set of dependencies that *all* resolutions in
    # the resulting set should have, regardless of nesting.
    def to_resolution_set(*, inherit = Set(Resolution::Dependency).new, set = ResolutionSet.new)
      # All resolutions under this container will inherit the
      # following dependencies.
      deps = inherit.concat(@runnables.select(Resolution::Dependency).to_set)

      @runnables.each do |runnable|
        case runnable
        when RunnableContainer
          resolution = runnable.to_resolution_set(inherit: deps.dup)
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

    @primary_rewrite = false

    def thorough_rewrite
      @primary_rewrite = true

      # Perform the first rewrite. This will take care of the
      # easy stuff.
      rewrite

      @primary_rewrite = false

      return unless abspath = @env.abspath?

      recursive_nonterminal_map! do |nonterminal, container|
        next nonterminal unless container.from?(@env)

        child = container.child(abspath, transparent: true)
        child.append(nonterminal)
        child.rewrite

        child
      end

      rewrite
    end

    def specialize(root : RunnableRoot, container : RunnableContainer)
      return if empty?

      rewrite

      container.append(self)
    end

    def to_s(io, indent = 0, lead = indent)
      io << " " * lead
      io << "Transparent" if transparent?
      io << "Container[" << @dir << "]:\n"

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

    # Returns the user's current working directory. It is also
    # sometimes referred to as the "primary origin", "origin" as
    # in "primary origin (source) of files".
    getter cwd

    def initialize(@disk : Disk, @cwd : Path)
      # Define default (& current working directory) environment.
      @envs[@cwd] = @envs[nil] = defenv(disk.env?(@cwd))
    end

    @wishes = [] of RunnableQuery

    # Appends *query* to the wishlist of this runnable root (the
    # wishlist is like "outbound queries" or "preload requests").
    #
    # Wishes are picked up from the wishlist by outer infrastructure
    # and loaded distinctly. The only guarantee is that they will
    # indeed be *preloaded* relative to the query that made the wish,
    # meaning loaded some time before it.
    #
    # Does nothing if *query* is already in the wishlist.
    def wish(query : RunnableQuery)
      return if query.in?(@wishes)

      @wishes << query
    end

    # Yields queries from this runnable root's wishlist of queries.
    #
    # See `wish`.
    def each_wish(& : RunnableQuery ->)
      @wishes.each { |wish| yield wish }
    end

    @explicit = [] of RunnableQuery

    # Marks *query* as explicit ("hand-written") within this
    # runnable root.
    def defexplicit(query : RunnableQuery)
      return if query.in?(@explicit)

      @explicit << query
    end

    @envs = {} of Path? => RunnableEnvironment

    # Returns the `RunnableEnvironment` for *path*, creating one if
    # it does not exist.
    #
    # Note that *path* can be nil, which means the created/returned
    # environment will be so to speak "virtual". The only difference
    # being the "virtual" environment's response to disk-related
    # questions. Namely it'll answer does-not-exist (or something
    # like that) to any disk-related question.
    #
    # Note also, that only one pathless environment can ever created;
    # as a consequence, all runnable containers that have no environments
    # will share one pathless runnable environment.
    def defenv(path : Path?)
      @envs[path] ||= RunnableEnvironment.new(self, path)
    end

    # Returns the default runnable environment.
    #
    # Currently, current working directory environment is used as the
    # default runnable environment.
    #
    # Note that if the current working directory does not have an
    # environment, a "virtual", pathless environment is returned
    # (see `defenv`).
    def default_env : RunnableEnvironment
      @envs[nil]
    end

    @preambles = {} of RunnableGroup => String
    @containers = {} of RunnableGroup => RunnableContainer

    # Assigns *container* to the given *group*.
    #
    # This is the only way someone from the outside can (reliably)
    # get the container of a group.
    #
    # *overwrite* specifies whether the existing container for *group*
    # should be overwritten with *container*.
    #
    # Returns the container that was assigned to *group*.
    def assign(
      group : RunnableGroup, *,
      container : RunnableContainer,
      overwrite = true
    ) : RunnableContainer
      if overwrite
        @containers[group] = container
      else
        @containers[group] ||= container
      end
    end

    # Assigns *preamble* to the given runnable *group*.
    def assign(group : RunnableGroup, *, preamble : String)
      @preambles[group] = preamble
    end

    # Returns the container assigned to *group*.
    #
    # Raises if *group* is neither an application nor a library.
    def containerof(group : RunnableGroup) : RunnableContainer
      containerof?(group) || raise "BUG: container was not assigned to #{group}"
    end

    # Returns the container of an application or library *group*, or
    # nil if *group* is neither an application nor a library.
    def containerof?(group : RunnableGroup) : RunnableContainer?
      @containers[group]?
    end

    # Returns the preamble of *group*, or nil if it has none.
    def preambleof?(group : RunnableGroup) : String?
      @preambles[group]?
    end

    @receivers = Set(SignalReceiver).new

    # Subscribes *receiver* to this runnable root.
    def subscribe(receiver : SignalReceiver)
      @receivers << receiver
    end

    # Unsubscribes *receiver* from this runnable root.
    def unsubscribe(receiver : SignalReceiver)
      @receivers.delete(receiver)
    end

    # Sends *signal* to all `SignalReceiver`s subscribed to this
    # runnable root.
    def send(signal : Signal)
      @receivers.each &.receive(signal)
    end

    # Creates and returns a new primary `RunnableContainer`.
    def new_primary_container : RunnableContainer
      RunnableContainer.new(self, @cwd, defenv(@cwd))
    end

    # Creates and returns a permission server in the given runnable
    # environment *env* and capability collection *caps*.
    def serve_permissions(to env : RunnableEnvironment) : PermissionServer
      PermissionServer.new(env, @explicit).tap { |server| subscribe(server) }
    end

    @depth = 0

    # :nodoc:
    def down(caller)
      if @depth > RESOLVER_RECURSION_LIMIT
        raise RunnableError.new("recursion depth exceeded: maybe there is a dependency cycle?", caller)
      end

      @depth += 1
    end

    # :nodoc:
    def up
      @depth -= 1
    end

    @flags = Set(String).new

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

    # Yields all set (true) flags.
    def each_set_flag(& : String ->)
      @flags.each { |flag| yield flag }
    end
  end

  # Permission server allows to prompt the user for permissions, and
  # save the user's choices in the *permissions file*.
  #
  # Note that you have to manually call `load` and `save` when
  # appropriate in order to load permissions from disk, and save
  # them on disk for better user experience.
  class PermissionServer
    include SignalReceiver

    # Creates a new permission server.
    #
    # *resolver* is the resolver with which this server will talk about
    # resolver-related things.
    #
    # *explicit* is a list of explicit runnable queries. An explicit
    # query is that query which was specified manually, e.g. via the
    # arguments. In other words, the user had to *type it* here and
    # now rather than "acquire" it from somewhere unknowingly. This
    # list is mainly used to be less annoying when it comes to asking
    # for permissions.
    def initialize(@env : RunnableEnvironment, @explicit : Array(RunnableQuery))
      @permissions = {} of Resolution::Dependency::Signature => Permission

      @ask = ToAskDo::Fn.new { }
      @answer = ToAnswerDo::Fn.new { }
    end

    def receive(signal : Signal)
      case signal
      when ToAskDo    then @ask = signal.fn
      when ToAnswerDo then @answer = signal.fn
      when DoDiskLoad then load
      when DoDiskSave then save
      end
    end

    # Fills the permissions hash with saved permissions.
    def load
      return unless permissions = @env.permissions?

      content, path = permissions

      begin
        CSV.each_row(content.strip) do |(dependent, dependency, state)|
          next unless id = state.to_i?
          next unless permission = Permission.from_value?(id)

          @permissions[{dependent, dependency}] = permission
        end
      rescue IndexError # Row not found, column not found etc.
        raise ResolverError.new("malformed 'permissions' file: #{path}")
      end
    end

    # Flushes the internal permissions store to disk. Can create the
    # permissions file, if necessary.
    #
    # Note: this method does nothing in case the internal permissions
    # store is empty.
    def save
      return unless @permissions.values.any?(&.allowed?)

      @env.permissions do |io|
        CSV.build(io) do |builder|
          @permissions.each do |(dependent, dependency), permission|
            # Do not save undecided / denied because such decision
            # is going to be hard to revert, and could have been
            # made by mistake anyway.
            next if permission.undecided? || permission.denied?

            builder.row(dependent, dependency, permission.to_i)
          end
        end
      end
    end

    # Returns a brief description of *dependency*.
    def brief(dependency : RunnableCapability) : String
      @env.brief(dependency)
    end

    # Asks user a *question*, and returns the answer or an empty
    # string in case EOF was received.
    def ask?(question : String) : String?
      @ask.call(question)
    end

    # Prints *answer* so that it can be seen by the user.
    def answer(answer : String)
      @answer.call(answer)
    end

    # Returns whether *dependency* is explicit.
    #
    # This is done by checking whether the *first* `RunnableQuery`
    # ancestor of *dependency* is in the explicit list. See `new`
    # to learn what "explicitness" means.
    def explicit?(dependency : Resolution::Dependency) : Bool
      dependency.each_ancestor do |ancestor|
        next unless ancestor.is_a?(RunnableQuery)
        return @explicit.any? &.same?(ancestor)
      end

      false
    end

    # Queries (possibly prompts) and returns the permission state of
    # *dependency* for the given *container*.
    def query_permission?(container : RunnableContainer, dependency : Resolution::Dependency)
      @permissions[dependency.signature(container)] ||= dependency.prompt?(self, for: container)
    end
  end

  # A mutable response object which is tightly coupled to `Session`,
  # designed for reuse throughout multiple (rounds of) queries to
  # the latter.
  struct Response
    include SignalReceiver

    # Represents the way a resolution set was accepted.
    enum AcceptionRoute
      # The resolution set was accepted because of a *wish*: some
      # runnable out there "wished" that runnables from the set were
      # there, and here they are.
      Wish

      # The resolution set was explicitly mentioned (queried for).
      Query
    end

    def initialize
      @accepted = [] of {AcceptionRoute, ResolutionSet}
      @ignored = [] of Runnable
      @rejected = [] of Runnable
      @wishlist = [] of RunnableQuery
    end

    def receive(signal : Signal)
      case signal
      when RunnableIgnored
        @ignored << signal.runnable
      end
    end

    # Returns `true` if this response does not "wish" to make any more
    # queries before its accepted sets can be inspected.
    def wishless? : Bool
      @wishlist.empty?
    end

    # Returns whether this response is successful, in that it has no
    # rejected runnables.
    def successful? : Bool
      @rejected.empty?
    end

    # Joins all accepted resolution sets of this response into one
    # large resolution set, and returns it. Does not distinguish between
    # *queried-for* and *wished* resolution sets.
    #
    # See `AcceptionRoute` to learn about the difference between
    # *queried-for* and *wished* routes of set acception.
    def accepted_set : ResolutionSet
      accepted_set = ResolutionSet.new
      @accepted.each do |(_, set)|
        accepted_set.append(set)
      end
      accepted_set
    end

    # Joins all *queried-for* accepted resolution sets of this response
    # into one large resolution set, and returns it.
    #
    # See `AcceptionRoute` to learn about the difference between
    # *queried-for* and *wished* routes of set acception.
    def queried_for_set : ResolutionSet
      queried_for_set = ResolutionSet.new
      @accepted.each do |(route, set)|
        next unless route.query?
        queried_for_set.append(set)
      end
      queried_for_set
    end

    # Yields runnables that were rejected.
    def each_rejected_runnable(& : Runnable ->)
      @rejected.each { |runnable| yield runnable }
    end

    # Yields runnables that were ignored.
    def each_ignored_runnable(& : Runnable ->)
      @ignored.each { |runnable| yield runnable }
    end

    # Yields wishes from this response's wishlist, then clears
    # the wishlist (so that this response can perhaps be reused).
    def drop_wish(& : RunnableQuery ->)
      @wishlist.each { |wish| yield wish }
      @wishlist.clear
    end

    # :nodoc:
    def accept(session : Session, root : RunnableRoot, route : AcceptionRoute, prepend : Bool) : ResolutionSet
      container = root.new_primary_container

      session.each_query { |query| container.append(query) }
      session.each_explicit { |query| root.defexplicit(query) }

      begin
        root.subscribe(self)

        container.thorough_rewrite
        container.flatten!

        session.on_container_rewritten(container)
      ensure
        root.unsubscribe(self)
      end

      container.recursive_nonterminal_each do |nonterminal|
        prepend ? @rejected.unshift(nonterminal) : @rejected.push(nonterminal)
      end

      root.each_wish do |wish|
        prepend ? @wishlist.unshift(wish) : @wishlist.push(wish)
      end

      set = container.to_resolution_set

      prepend ? @accepted.unshift({route, set}) : @accepted.push({route, set})

      set
    end
  end

  # A resolver session interacts with a `RunnableRoot` in a way that
  # allows you to *query*. Querying is done by `push`ing some queries,
  # and then `pop`ping them "into" a `Response` object which you should
  # create beforehand, and which you own.
  #
  # ```
  # session = Resolver::Session.new(root)
  # session.push("foo")
  # session.push("bar")
  # session.push("baz")
  #
  # response1 = Resolver::Response.new
  # session.pop(response1)
  #
  # # Re-use the same session. Queries were popped, so the session
  # # is clean.
  # session.push("xyzzy")
  # session.push("byzzy")
  #
  # response2 = Resolver::Response.new
  # session.pop(response2)
  #
  # # Run the accepted stuff from the responses...
  # response1.accepted_set.each_designation(root, &.run)
  # response2.accepted_set.each_designation(root, &.run)
  # ```
  class Session
    def initialize(@root : RunnableRoot)
    end

    @on_container_rewritten = Set(RunnableContainer ->).new

    # Registers *callback* to be called when a runnable container
    # is thoroughly rewritten.
    def on_container_rewritten(&callback : RunnableContainer ->)
      on_container_rewritten(callback)
    end

    # :ditto:
    def on_container_rewritten(callback : RunnableContainer ->)
      @on_container_rewritten << callback
    end

    # :nodoc:
    def on_container_rewritten(container : RunnableContainer)
      @on_container_rewritten.each &.call(container)
    end

    @explicit = [] of RunnableQuery

    # Yields only those queries from the query list that were
    # marked as explicit.
    def each_explicit(& : RunnableQuery ->)
      @explicit.each { |query| yield query }
    end

    @queries = [] of RunnableQuery

    # Yields all queries from the query list.
    def each_query(& : RunnableQuery ->)
      @queries.each { |query| yield query }
    end

    # Appends *query* to the list of queries to be resolved during
    # this session; allows to mark it as *explicit* ("hand-written")
    # if necessary.
    def push(query : RunnableQuery, explicit = false)
      @queries << query
      @explicit << query if explicit
    end

    # :ditto:
    def push(query : Query, explicit = false)
      push(RunnableQuery.new(query), explicit)
    end

    # Appends the entire array of *queries* to the list of queries
    # to be resolved during this session; allows to mark *all* of
    # them as *explicit* ("hand-written") if necessary.
    def push(queries : Array(RunnableQuery), explicit = false)
      @queries.concat(queries)
      @explicit.concat(queries) if explicit
    end

    # :ditto:
    def push(queries : Array(Query) | Array(String) | Array(Path), explicit = false)
      push(queries.map { |query| RunnableQuery.new(query) }, explicit)
    end

    @cleared = Set(RunnableQuery).new

    # Resolves the list of queries that were `push`ed, returns the single
    # resolution set comprised of resolutions for those queries that
    # were accepted by the resolver.
    #
    # Also fills *response*, see `ResolverResponse` for what you can
    # get out of it.
    def pop(response : Response) : ResolutionSet
      pop(response, route: Response::AcceptionRoute::Query, prepend: false)
    end

    private def pop(response : Response, route : Response::AcceptionRoute, prepend : Bool) : ResolutionSet
      accepted = response.accept(self, @root, route, prepend)

      @cleared.concat(@queries)
      @queries.clear
      @explicit.clear

      response.drop_wish do |wish|
        next if wish.in?(@cleared)

        @queries << wish
      end

      unless @queries.empty?
        pop(response, route: Response::AcceptionRoute::Wish, prepend: true)
      end

      accepted
    end
  end
end

# A very high-level interface to the Novika resolver. Designed as one-
# shot, meaning you shouldn't reuse the same object twice or call
# `resolve?` twice. As a protection, calling `resolve?` twice will raise.
#
# See `Session` and `Response` if you want a lower-level interface.
#
# ```
# resolver = Novika::RunnableResolver.new(cwd: Path[Dir.current], args: ["repl"])
#
# # Define 'gets' and 'print' to ask for permissions.
#
# resolver.on_permissions_gets do |string|
#   print string
#   gets
# end
#
# resolver.on_permissions_print do |string|
#   print string
# end
#
# # Run "repl" and everything it requested.
#
# resolver.after_permissions(&.run)
# resolver.resolve?
# ```
class Novika::RunnableResolver
  include Resolver

  # An object that helps you do high-level things with a `Response`.
  class ResponseHook
    # Returns the `Response` object.
    getter response

    def initialize(@resolver : RunnableResolver, @root : RunnableRoot, @response : Response)
    end

    # Yields preambles of apps and libs that were queried for in
    # arguments to `RunnableResolver#new` specifically, followed by
    # their corresponding runnable groups.
    def each_queried_for_preamble_with_group(& : String, RunnableGroup ->)
      @response.queried_for_set.each_preamble_with_group(@root) do |preamble, group|
        next unless query = group.ancestors.find(RunnableQuery)
        next unless @resolver.argument?(query)

        yield preamble, group
      end
    end
  end

  # An object that helps you do high-level things with a `ResolutionSet`
  # for the entire *program*.
  #
  # A Novika program is basically a collection of properly arranged
  # Novika scripts. This is represented by a single `ResolutionSet`,
  # which is an ordered set. It being a set means that you cannot
  # execute a single script twice in one session of the resolver,
  # that is, globally.
  class ProgramHook
    # Returns the program `ResolutionSet`.
    getter program

    def initialize(@resolver : RunnableResolver, @root : RunnableRoot, @program : ResolutionSet)
    end

    # Makes and yields designations for the program.
    #
    # See `Designation` to learn what they are.
    def each_designation(& : Designation ->)
      @program.each_designation(@root) { |designation| yield designation }
    end
  end

  # Same as `ProgramHook` but also allows you to run the program.
  class PermissionsHook < ProgramHook
    # Returns the list of designations in the program.
    def designations : Array(Designation)
      designations = [] of Designation
      @program.each_designation(@root) do |designation|
        designations << designation
      end
      designations
    end

    # Runs the program.
    def run
      @program.each_designation(@root, &.run)
    end
  end

  @cwd : Path
  @args : Array(RunnableQuery)

  # Creates a new resolver for the given current working directory
  # *cwd* and query arguments *args*.
  #
  # See `RunnableResolver`.
  def initialize(cwd : Path, args : Array(Query))
    disk = Disk.new

    unless cwd = disk.dir?(cwd)
      raise ResolverError.new("missing or malformed current working directory")
    end

    @cwd = cwd
    @args = args.map { |query| RunnableQuery.new(query) }

    @root = RunnableRoot.new(disk, @cwd)
    @root.set_flag("bsd", {{ flag?(:bsd) }})
    @root.set_flag("darwin", {{ flag?(:darwin) }})
    @root.set_flag("dragonfly", {{ flag?(:dragonfly) }})
    @root.set_flag("freebsd", {{ flag?(:freebsd) }})
    @root.set_flag("linux", {{ flag?(:linux) }})
    @root.set_flag("netbsd", {{ flag?(:netbsd) }})
    @root.set_flag("openbsd", {{ flag?(:openbsd) }})
    @root.set_flag("unix", {{ flag?(:unix) }})
    @root.set_flag("windows", {{ flag?(:windows) }})

    @session = Session.new(@root)
    @response = Response.new
    @resolved = false
  end

  # Returns whether *query* was passed as an argument to this resolver.
  def argument?(query : RunnableQuery)
    @args.any? &.same?(query)
  end

  # Helps get rid of `push(); pop()`s. Returns resolution set specifically
  # for the pushed query if the response is successful, otherwise nil.
  private def sched?(*args, **kwargs) : ResolutionSet?
    @session.push(*args, **kwargs)

    set = @session.pop(@response)
    set if @response.successful?
  end

  # Called when some container under this resolver was thoroughly rewritten.
  #
  # You'll have to do additional checks to figure out where the
  # container came from. This is mainly an inspection method.
  def after_container_rewritten(&callback : RunnableContainer ->)
    @session.on_container_rewritten(callback)
  end

  @after_response = Set(ResponseHook ->).new

  # Registers *callback* to run after a valid response is formed.
  def after_response(&callback : ResponseHook ->)
    @after_response << callback
  end

  private def on_response(response : Response)
    @after_response.each do |callback|
      callback.call ResponseHook.new(self, @root, response)
    end
  end

  @after_program = Set(ProgramHook ->).new

  # Registers *callback* to run after a valid Novika program is formed.
  # See `ProgramHook` to learn what is considered a Novika program.
  def after_program(&callback : ProgramHook ->)
    @after_program << callback
  end

  private def on_program(program : ResolutionSet)
    @after_program.each do |callback|
      callback.call ProgramHook.new(self, @root, program)
    end
  end

  @after_permissions = Set(PermissionsHook ->).new

  # Registers *callback* to run after a valid Novika program is formed,
  # and permissions are given.
  def after_permissions(&callback : PermissionsHook ->)
    @after_permissions << callback
  end

  private def on_permissions(program : ResolutionSet)
    @after_permissions.each do |callback|
      callback.call PermissionsHook.new(self, @root, program)
    end
  end

  @on_permissions_gets = ->(_string : String) { raise "BUG: can't ask anything..." }
  @on_permissions_print = ->(_string : String) { raise "BUG: can't say anything..." }

  # Registers a handler for permissions `gets`. Overrides the previous
  # handler, if any.
  def on_permissions_gets(&@on_permissions_gets : String -> String?)
  end

  # Registers a handler for permissions `print`. Overrides the previous
  # handler, if any.
  def on_permissions_print(&@on_permissions_print : String ->)
  end

  # Called when the user runs `$ novika` in a directory that is neither
  # an app nor a lib; tries to schedule `__default__`.
  private def resolve_cwd?(manifest : Manifest::Absent) : Bool
    !!sched?("__default__")
  end

  # Called when the user runs `$ novika` in a directory that is a Novika
  # app; just schedules the app.
  private def resolve_cwd?(manifest : Manifest::App) : Bool
    !!sched?(@cwd)
  end

  # Called when the user runs `$ novika` in a directory that is a Novika
  # lib. Looks at the configured `__lib_wrapper__` and schedules that.
  # Raises if the latter isn't an app.
  private def resolve_cwd?(manifest : Manifest::Lib) : Bool
    return false unless sched?(@cwd)
    return false unless wrapper = sched?("__lib_wrapper__")

    unless wrapper.app?
      raise ResolverError.new("autoloading failed: expected __lib_wrapper__ to be an app")
    end

    true
  end

  # Performs resolution. Returns `true` if resolution is successful,
  # `false` if the resolver had nothing to do (not even an error).
  def resolve? : Bool
    if @resolved
      raise "BUG: attempt to RunnableResolver#resolve? twice"
    end

    if @args.empty?
      manifest = Manifest.find(@root.disk, @cwd)

      return false unless resolve_cwd?(manifest)
    else
      sched?(@args, explicit: true)
    end

    # Having an unsuccessful response is an error, and means some
    # runnables were rejected.
    raise ResponseRejectedError.new(@response) unless @response.successful?

    on_response(@response)

    # Okay, so we have one huge response which seems like a valid one.
    # Now we need to form a resolution set from it.
    program = @response.accepted_set

    # Listing more than one app is an error. Note that in manifests,
    # apps are ignored (therefore see above), so here we're basically
    # handling situations such as `$ novika create/app create/lib`.
    apps = program.unique_apps

    raise MoreThanOneAppError.new(apps) if apps.size > 1

    # The program resolution set looks OK now.
    on_program(program)

    @root.send(DoDiskLoad.new)
    @root.send(ToAskDo.new(@on_permissions_gets))
    @root.send(ToAnswerDo.new(@on_permissions_print))

    # Enable dependencies required by the program resolution set.
    #
    # Currently we do it in a way that completely throws away any
    # actual usefulness/safety guarantees the dependency system
    # is designed to provide. There are reasons but hopefully this
    # isn't going to be the case in the future.
    program.each_unique_dependency_with_dependents do |dependency, dependents|
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

        # Find the container that maps to the group/lib.
        container = @root.containerof(group)
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

    @root.send(DoDiskSave.new)

    on_permissions(program)

    # Mark that we don't want to resolve?() again.
    @resolved = true

    true
  end
end
