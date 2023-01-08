module Novika
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

    # Returns whether this folder is an app folder.
    #
    # An app folder is that which contains a `.nk.app` file.
    getter? app : Bool

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
                   @app = false,
                   @core = false,
                   @explicit = true)
    end

    def_equals_and_hash path, explicit?
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

    # Holds feature ids identified in the initial list of
    # runnables by this resolver.
    #
    # Note: resolver uses bundle in a read-only manner. You
    # will have to enable the features yourself (if that's
    # what you want to do).
    getter features = Set(String).new

    # Holds runnables which have not been identified. You
    # can handle them as you wish: as per this resolver,
    # they are unrelated to Novika.
    getter unknowns = Set(String).new

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
      File.file?(path / ".nk.app")
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

    # Recursively visits directories starting at, and
    # including, *root*, and creates `Folder`s for their
    # corresponding paths.
    #
    # Subdirectories that are apps themselves are skipped
    # entirely. Subdirectories called 'core' are autoloaded
    # as expected.
    private def load(store : Hash(Path, Folder), root : Path, app : Bool, core : Bool, explicit = true)
      return if store.has_key?(root)

      entry = root / "#{root.stem}.nk"
      folder = store[root] = Folder.new(
        path: root,
        entry: File.file?(entry) ? entry : nil,
        app: app,
        core: core,
        explicit: explicit,
      )

      Dir.glob(root / "*.nk") do |path|
        # Skip entry path. We've looked at it above.
        next if entry == (path = Path[path])

        folder.files << path
      end

      Dir.glob(root / "*/") do |path|
        next if app?(path = Path[path])

        # Disallow apps but allow core. This configuration
        # seems to work, but still smells weirdly!
        load(store, path, app: false, core: core?(path), explicit: explicit)
      end
    end

    # :ditto:
    private def load(path : Path, app = false, core = false, explicit = true)
      store = {} of Path => Folder
      load(store, path, app, core, explicit)
      store.each_value do |folder|
        folders << folder
      end
    end

    # Resolves: finda
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
      # This 'core' is allowed to be an app.
      cwd_core.try { |dir| load(dir, core: true, app: app?(@cwd), explicit: false) }

      @runnables.each do |runnable|
        if @bundle.has_feature?(runnable)
          features << runnable
          next
        end

        # Unless runnable exists as a directory/file in
        # current working directory, or in Novika
        # environment directory, mark as unknown and go
        # to the next runnable.
        unless path = expand_runnable_path?(Path[runnable])
          unknowns << runnable
          next
        end

        if File.directory?(path)
          load(path, app: app?(path))
          next
        end

        unless File.file?(path)
          unknowns << runnable
          next
        end

        if shared_object?(path)
          shared_objects << path
          next
        end

        files << path
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
