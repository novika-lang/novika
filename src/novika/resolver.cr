require "csv"

module Novika
  MANIFEST_APP         = ".nk.app"
  MANIFEST_LIB         = ".nk.lib"
  MANIFEST_PERMISSIONS = "permissions"

  PERMISSION_YES = "1"
  PERMISSION_NO  = "0"

  # Specifies what a particular folder is, for Novika.
  struct Folder
    # Returns the path to this folder.
    getter path : Path

    # Returns full path to the entry file, found inside this
    # folder. For example, given this folder is called `foo`,
    # its entry file is going to be called `foo.nk`.
    #
    # Returns nil if there is no entry file.
    getter? entry : Path?

    # Returns full paths to *files* found in this folder.
    getter files : Set(Path)

    # Returns the path to the app manifest file. If non-nil,
    # then this folder is considered a Novika app.
    getter? app : Path?

    # Returns whether this folder is a core folder.
    #
    # A core folder is that which has the name 'core'.
    getter? core : Bool

    # Returns whether this folder was specified in the runnable
    # list, explicitly.
    getter? explicit : Bool

    def initialize(@path,
                   @entry = nil,
                   @files = Set(Path).new,
                   @app = nil,
                   @core = false,
                   @explicit = true)
    end

    # Returns the path to the lib manifest file. If non-nil,
    # then this folder is considered a Novika app.
    def lib?
      path / MANIFEST_LIB unless app?
    end

    # Reads and returns the contents of '.nk.app' or '.nk.lib',
    # depending on the type of this folder (app or otherwise).
    #
    # Returns nil if neither exists.
    def manifest?
      if (mpath = app? || lib?) && File.readable?(mpath)
        File.read(mpath)
      end
    end

    def_equals_and_hash path, explicit?
  end

  # Holds information about a feature request.
  struct FeatureRequest
    # Returns the path to the folder for which the feature
    # was requested.
    getter root : Path

    # Returns the identifier of the feature.
    getter id : String

    # Returns whether the request was typed in maually (true),
    # or picked up from a .nk.lib or .nk.app file (false).
    getter? manual : Bool

    def initialize(@resolver : RunnableResolver, @id, @manual)
      @root = resolver.cwd
    end

    # Returns whether this feature request is allowed by the user.
    #
    # This feature request is always allowed if it is provided
    # manually.
    #
    # If not, tries reading the permissions file in the Novika
    # environment directory. If the user had made the decision
    # already, returns that decision. Otherwise, yields, assuming
    # the block will ask the user to decide. If the return value
    # of the block is true, it is written as the decision to the
    # permissions file. The decision is returned.
    #
    # *always_ask* can be used to force the user to decide with the
    # help of the block, regardless of what is in the permissions
    # file. The new decision will then be written to the
    # permissions file.
    #
    # If the permissions file is invalid for some reason, it
    # is left intact; in such case, the user will have to decide
    # anew every time, as if there was no permissions file at all.
    def allowed?(always_ask = false, & : self -> Bool) : Bool
      return true if manual?

      @resolver.permissions do |io|
        rows = CSV.parse(io)

        # Verification pass. Ensure all rows have three elements,
        # and permission is a '0' or '1'.
        valid =
          rows.all? do |row|
            row.size == 3 && row[2].in?(PERMISSION_NO, PERMISSION_YES)
          end

        if valid && always_ask
          # In always ask mode, we'll need to clear the previous
          # row (if any).
          rows.reject! { |(root, id)| p({root, id} == {@root.to_s, @id}) }
        elsif valid
          # Otherwise, we need to find & return the existing
          # permission (again, if any).
          rows.each do |(root, id, perm)|
            return perm == PERMISSION_YES if {root, id} == {@root.to_s, @id}
          end
        end

        # In any other case, ask the user.
        perm = yield self

        return perm unless valid

        io.rewind
        CSV.build(io) do |csv|
          rows.each { |row| csv.row(row) }
          csv.row(@root, @id, PERMISSION_YES) if perm
        end

        return perm
      end

      false
    end

    def_equals_and_hash root, id
  end

  # `RunnableResolver`'s (or resolver's for short) main
  # objective is -- who'd have guessed it! -- to *resolve* a
  # list of *runnables* to the appropriate file paths,
  # `Folder`s, apps, and feature requests.
  #
  # It also puts them in different lists, so that it's a bit
  # easier for you to take care of them, after resolver has
  # done its job.
  #
  # Immediately after `resolve?`, all `folders`, `apps`,
  # `files`, and `features` identified by this resolver
  # are guaranteed to exist. If an all-time guarantee is
  # required, you should establish watchers and diff the
  # arrays as appropriate.
  #
  # ```
  # resolver = RunnableResolver.new(["repl"], bundle, Path[Dir.current], Path.home)
  # unless resolver.resolve?
  #   abort "Failed to resolve!"
  # edn
  #
  # resolver.features.each { |feature_id| bundle.enable(feature_id) }
  # resolver.unknowns.each { |unknown| puts "Not a runnable, skip: #{unknown}" }
  #
  # # resolver.folders.each { |folder| ... }
  # # resolver.files.each { |file| ... }
  # # resolver.apps.each { |file| ... }
  # # Do whatever you want with them!
  # ```
  class RunnableResolver
    # Holds the folders this resolver identified as apps in
    # the initial list of runnables.
    #
    # This is determined by the presence of `.nk.app`, in
    # what would be otherwise considered a folder.
    getter apps = Set(Folder).new

    # Holds paths to Novika files in the initial list of
    # runnables, as per this resolver.
    getter files = Set(Path).new

    # Holds non-application folders in the initial list of
    # runnables, as per this resolver.
    getter folders = Set(Folder).new

    # Holds platform-specific, `dlopen`-able shared objects
    # (.so in Linux, .dll in Windows, .dylib in MacOS), later
    # consumed by the FFI/library machinery.
    #
    # Note that we don't actually check whether they *are* shared
    # objects or are simply files with an .so (.dll, .dylib) file
    # extension.
    #
    # Mostly for safety, shared objects are not loaded automatically.
    # You need to list them by hand in the initial runnable list; or
    # manually ask feature ffi to get them, in code.
    getter shared_objects = Set(Path).new

    # Holds feature requests identified in the initial list of
    # runnables by this resolver (those with manual set to true),
    # as well as features requested in lib or app manifests
    # (those with manual set to false).
    #
    # Note: resolver uses bundle in a read-only manner. You
    # will have to enable the features yourself (if that's
    # what you want to do).
    getter features = Set(FeatureRequest).new

    # Holds runnables which have not been identified. You
    # can handle them as you wish: as per this resolver,
    # they are unrelated to Novika.
    getter unknowns = Set(String).new

    # Returns the current working directory for this resolver.
    #
    # May change as resolution progresses.
    getter cwd : Path

    # Initializes a `RunnableResolver`.
    #
    # *runnables* is the list of runnables to resolve.
    #
    # *bundle* is the bundle that will be used to verify
    # whether a runnable is a feature ids.
    #
    # *cwd* specifies the directory that this resolver will
    # consider its current working directory.
    #
    # *userhome* is assumed to be user's home directory.
    #
    # Defaults for the last two are sane enough.
    def initialize(
      @runnables : Array(String),
      @bundle : Bundle,
      @cwd = Path[Dir.current],
      @userhome = Path.home
    )
    end

    # If it exists, returns *path* expanded in the current
    # working directory. Otherwise, returns nil.
    private def expand_in_cwd?(path : Path)
      path if File.exists?(path = path.expand(@cwd))
    end

    # Path to the 'core' directory in the current working
    # directory. Returns nil if it does not exist.
    private getter cwd_core : Path? do
      path if File.directory?(path = @cwd / "core")
    end

    # Path to the best-fit Novika environment directory.
    # Returns nil if no Novika environment directories
    # exist.
    #
    # *Global environment* can only be called '.novika', and
    # is usually found in '/home/username'. *Local environment*,
    # if present, takes precedence over the global environment,
    # and may be called either '.novika', or 'env'.
    private getter env : Path? do
      path if File.directory?(path = @cwd / ".novika") ||
              File.directory?(path = @cwd / "env") ||
              File.directory?(path = @userhome / ".novika")
    end

    # If it exists, returns *path* expanded in the Novika
    # environment directory. Otherwise, returns nil.
    private def expand_in_env?(path : Path)
      env.try { |env| path if File.exists?(path = path.expand(env)) }
    end

    # Path to the 'core' directory path in the Novika
    # environment directory. Returns nil if it does not
    # exist.
    private getter env_core : Path? do
      env.try { |env| path if File.directory?(path = env / "core") }
    end

    # Tries to expand runnable *path* to that in the current
    # working directory, or, if it doesn't exist there, to
    # that in the Novika environment directory. If both do
    # not exist, returns nil.
    def expand_runnable_path?(path : Path)
      expand_in_cwd?(path) || expand_in_env?(path)
    end

    # Returns whether *path* is an app directory (contains '.nk.app').
    private def app?(path : Path)
      File.file?(path / MANIFEST_APP)
    end

    # Returns whether *path* is a 'core' directory.
    private def core?(path : Path)
      path.dirname == "core"
    end

    # Returns whether *path* is a system-specific shared object.
    private def shared_object?(path : Path)
      {% if flag?(:darwin) %}
        path.extension == ".dylib"
      {% elsif flag?(:windows) %}
        path.extension == ".dll"
      {% elsif flag?(:unix) %}
        path.extension == ".so"
      {% else %}
        false
      {% end %}
    end

    # Reads (creates, if necessary) a permissions file in the
    # Novika environment directory. Yields IO to the block.
    def permissions
      io = nil

      env.try do |env|
        unless File.exists?(env / MANIFEST_PERMISSIONS)
          File.touch(env / MANIFEST_PERMISSIONS)
        end

        io = File.open(env / MANIFEST_PERMISSIONS, "r+")
      end

      io ||= IO::Memory.new

      begin
        yield io
      ensure
        io.close
      end
    end

    # Recursively visits directories starting at, and
    # including, *root*, and creates `Folder`s for their
    # corresponding paths.
    #
    # Subdirectories that are apps themselves are skipped
    # entirely. Subdirectories called 'core' are autoloaded
    # as expected.
    private def load(store : Hash(Path, Folder), root : Path, app : Path?, core : Bool, explicit : Bool)
      return if store.has_key?(root)

      entry = root / "#{root.stem}.nk"
      folder = store[root] = Folder.new(
        path: root,
        entry: File.file?(entry) ? entry : nil,
        app: app,
        core: core,
        explicit: explicit,
      )

      if manifest = folder.manifest?
        _cwd, @cwd = @cwd, root

        manifest.each_line do |runnable|
          # Comments are allowed in the manifest files.
          next if runnable.starts_with?('#')

          resolve(runnable, manual: false)
        end

        @cwd = _cwd
      end

      Dir.glob(root / "*.nk") do |path|
        # Skip entry path. We've looked at it above.
        next if entry == (path = Path[path])

        folder.files << path
      end

      Dir.glob(root / "*/") do |path|
        next if app?(path = Path[path])

        # Disallow apps but allow core. This configuration
        # seems to work, but still smells weirdly!
        load(store, path, app: nil, core: core?(path), explicit: explicit)
      end
    end

    # :ditto:
    private def load(path : Path, app = nil, core = false, explicit = true)
      store = {} of Path => Folder
      load(store, path, app, core, explicit)
      store.each_value do |folder|
        folders << folder
      end
    end

    private def resolve(runnable : String, *, manual = true)
      if @bundle.has_feature?(runnable)
        features << FeatureRequest.new(self, runnable, manual)
        return
      end

      # Unless runnable exists as a directory/file in current
      # working directory, or in Novika environment directory,
      # mark as unknown.
      unless path = expand_runnable_path?(Path[runnable])
        unknowns << runnable
        return
      end

      if File.directory?(path)
        load(path, app: app?(path) ? path / MANIFEST_APP : nil)
        return
      end

      unless File.file?(path)
        unknowns << runnable
        return
      end

      if shared_object?(path)
        shared_objects << path
        return
      end

      files << path
    end

    def resolve? : Bool
      return false if @runnables.empty? && (!env_core || !cwd_core)

      # Autoload 'core' in the Novika environment directory.
      #
      # Note that '~/.novika' is never an app, even if there's
      # a '.nk.app' file there.
      env_core.try { |dir| load(dir, core: true, explicit: false) }

      # Autoload 'core' in the current working directory, if
      # there is 'core' there.
      #
      # This 'core' is allowed to be an app, but that should
      # be declared in the parent directory (cwd).
      cwd_core.try do |dir|
        load(dir, core: true,
          app: app?(@cwd) ? @cwd / MANIFEST_APP : nil,
          explicit: false
        )
      end

      @runnables.each { |runnable| resolve(runnable) }

      # If the user had manually enabled a feature, we enable
      # it for everyone.
      features.select(&.manual?).each do |feature|
        features.reject! do |other|
          feature.id == other.id && !other.manual?
        end
      end

      # Move apps from folders to the dedicated apps array.
      folders.reject! do |folder|
        # Reject if folder.app is true.
        folder.app?.tap { |app| apps << folder if app }
      end

      true
    end
  end
end
