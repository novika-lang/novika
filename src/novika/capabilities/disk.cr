module Novika::Capabilities
  abstract class IDisk
    include Capability

    def self.id : String
      "disk"
    end

    def self.purpose : String
      "exposes various disk-related (storage-related) words"
    end

    def self.on_by_default? : Bool
      false
    end

    # Returns whether *path* exists and is readable.
    abstract def can_read?(engine, path : Quote) : Boolean

    # Returns whether *path* exists.
    abstract def has?(engine, path : Quote) : Boolean

    # Returns whether *path* exists and points to a directory.
    abstract def has_dir?(engine, path : Quote) : Boolean

    # Returns whether *path* exists and points to a file.
    abstract def has_file?(engine, path : Quote) : Boolean

    # Returns whether *path* exists and points to a symlink.
    abstract def has_symlink?(engine, path : Quote) : Boolean

    # Returns whether directory pointed to by *path* is empty.
    # Returns nil if *path* does not point to a directory, or
    # if *path* does not exist.
    abstract def dir_empty?(engine, path : Quote) : Boolean?

    # Returns path quote which is the result of joining
    # *base* path and *child* path quotes using the
    # platform-specific path separator.
    abstract def join(engine, base : Quote, child : Quote) : Quote

    # Returns the working directory.
    abstract def pwd(engine) : Quote

    # Returns current user's home directory.
    abstract def home(engine) : Quote

    # Creates an empty file at *path*. Does nothing if *path*
    # already exists.
    abstract def touch(engine, path : Quote)

    # Creates an empty directory at *path*, including any
    # non-existing intermediate directories. Does nothing
    # if *path* already exists.
    abstract def mkdir(engine, path : Quote)

    # Copies source *src* (quote path to a file, symlink, or
    # directory) to destination *dst* (also a quote).
    #
    # If *src* is a directory, copies it recursively.
    #
    # Returns whether the operation was successful.
    abstract def copy(engine, src : Quote, dst : Quote) : Bool

    # Reads and returns the contents of file at *path*. Returns
    # nil if there is no file at *path*.
    abstract def read?(engine, path : Quote) : Quote?

    # (Over)writes content of file at *path* with *content*
    # quote. Returns nil if *path* doesn't exist or doesn't
    # point to a file.
    abstract def write?(engine, content : Quote, path : Quote) : Bool

    # (Over)writes content of file at *path* with *content*
    # byteslice. Returns nil if *path* doesn't exist or doesn't
    # point to a file.
    abstract def write?(engine, content : Byteslice, path : Quote) : Bool

    def inject(into target : Block)
      target.at("disk:has?", <<-END
      ( Pq -- true/false ): leaves whether Path quote exists
       on the disk.
      END
      ) do |engine, stack|
        path = stack.drop.a(Quote)
        has?(engine, path).onto(stack)
      end

      target.at("disk:canRead?", <<-END
      ( Pq -- true/false ): leaves whether Path quote exists
       and is readable.
      END
      ) do |engine, stack|
        path = stack.drop.a(Quote)
        can_read?(engine, path).onto(stack)
      end

      target.at("disk:hasDir?", <<-END
      ( Pq -- true/false ): leaves whether Path quote exists
       and points to a directory.
      END
      ) do |engine, stack|
        path = stack.drop.a(Quote)
        has_dir?(engine, path).onto(stack)
      end

      target.at("disk:hasFile?", <<-END
      ( Pq -- true/false ): leaves whether Path quote exists
       and points to a file.
      END
      ) do |engine, stack|
        path = stack.drop.a(Quote)
        has_file?(engine, path).onto(stack)
      end

      target.at("disk:hasSymlink?", <<-END
      ( Pq -- true/false ): leaves whether Path quote exists
       and points to a symlink.
      END
      ) do |engine, stack|
        path = stack.drop.a(Quote)
        has_symlink?(engine, path).onto(stack)
      end

      target.at("disk:dirEmpty?", <<-END
      ( Pq -- true/false ): leaves whether the directory at Path quote
       is empty. Dies if Path quote points to something other than
       a directory, or doesn't exist.
      END
      ) do |engine, stack|
        path = stack.drop.a(Quote)

        unless boolean = dir_empty?(engine, path)
          path.die("no directory at path")
        end

        boolean.onto(stack)
      end

      target.at("disk:join", <<-END
      ( Bpq Cpq -- Pq ): leaves Path quote, which is the result of joining
       Base path quote and Child path quote using the platform-specific
       path separator.

      ```
      'hello' 'world' disk:join leaves: 'hello/world' "On Unix"
      'hello' 'world' disk:join leaves: 'hello\\\\world' "On Windows"
      ```
      END
      ) do |engine, stack|
        cp = stack.drop.a(Quote)
        bp = stack.drop.a(Quote)
        join(engine, bp, cp).onto(stack)
      end

      target.at("disk:pwd", <<-END
      ( -- Pq ): leaves Path quote pointing to the current working directory.
      END
      ) do |engine, stack|
        pwd(engine).onto(stack)
      end

      target.at("disk:home", <<-END
      ( -- Pq ): leaves Path quote pointing to the user's home directory.
      END
      ) do |engine, stack|
        home(engine).onto(stack)
      end

      target.at("disk:touch", <<-END
      ( Pq -- ): creates an empty file at the location that Path quote
       points to. Does nothing if Path already exists.

      ```
      disk:pwd 'demo.txt' disk:join $: demoPath
      demoPath disk:touch 'Hey!' demoPath disk:write
      demoPath disk:read leaves: 'Hey!'
      ```
      END
      ) do |engine, stack|
        path = stack.drop.a(Quote)
        touch(engine, path)
      end

      target.at("disk:mkdir", <<-END
      ( Pq -- ): creates an empty directory at the location that Path
       quote points to. Also creates any non-existing intermediate
       directories. Does nothing if Path quote already points to an
       existing directory, file, symlink, etc.

      ```
      disk:pwd 'demo-dir-a' disk:join
               'demo-dir-b' disk:join
               'demo-dir-c' disk:join $: demoDirPath

      demoDirPath disk:mkdir
      demoDirPath disk:hasDir? leaves: true
      ```
      END
      ) do |engine, stack|
        path = stack.drop.a(Quote)
        mkdir(engine, path)
      end

      target.at("disk:copy", <<-END
      ( Spq Dpq -- ): copies whatever Source path quote points to, to the
       location that Destination path quote points to. If Source is a
       directory, it is copied recursively.

      If copy process failed (for instance if there is already something
      at Destination path quote), dies.

      ```
      disk:pwd 'a.txt' disk:join $: pathToA
      disk:pwd 'b.txt' disk:join $: pathToB

      pathToA disk:touch pathToA 'Content of file a.txt' disk:write
      pathToA pathToB disk:copy

      pathToA disk:read leaves: 'Content of file a.txt'
      pathToB disk:read leaves: 'Content of file a.txt'
      ```
      END
      ) do |engine, stack|
        dst = stack.drop.a(Quote)
        src = stack.drop.a(Quote)
        unless copy(engine, src, dst)
          src.die("could not copy")
        end
      end

      target.at("disk:read", <<-END
      ( Pq -- Q ): leaves Quote containing the content of the file that
       Path quote points to. Dies if Path quote points to nothing or if
       it points to something other than a file.

      ```
      disk:pwd 'a.txt' disk:join $: pathToA
      pathToA disk:touch 'Hello World' pathToA disk:write
      pathToA disk:read leaves: 'Hello World'
      ```
      END
      ) do |engine, stack|
        path = stack.drop.a(Quote)
        path.die("no file at path") unless contents = read?(engine, path)
        contents.onto(stack)
      end

      target.at("disk:write", <<-END
      ( Q/Bf Pq -- ): (over)writes the content of the file that Path quote
       points to, with the given Quote or Byteslice form. Dies if Path quote
       points to nothing or if it points to something other than a file.

      ```
      disk:pwd 'a.txt' disk:join $: pathToA
      pathToA disk:touch 'Hello World' pathToA disk:write
      pathToA disk:read leaves: 'Hello World'

      [ 0 $: count
        [ count dup 1 + =: count ]
      ] @: counter

      counter @: inc
      inc leaves: 0
      inc leaves: 1
      inc leaves: 2

      disk:pwd 'counter.nki' disk:join $: pathToCounter
      pathToCounter disk:touch

      "Save inc state using NKI and write the resulting byteslice
       to the file we've just created. Note that captureAll is similar
       to deep copy (it copies the *entire* Novika environment including
       the standard library), it's not the best way to do this but
       by far the easiest."
      (this -> inc nki:captureAll) pathToCounter disk:write

      pathToCounter disk:read toByteslice nki:toBlock @: incFromDisk

      incFromDisk leaves: 3
      incFromDisk leaves: 4
      incFromDisk leaves: 5
      ```
      END
      ) do |engine, stack|
        path = stack.drop.a(Quote)
        content = stack.drop.a(Quote | Byteslice)
        path.die("no file at path") unless write?(engine, content, path)
      end
    end
  end
end
