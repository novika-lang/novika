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
      ( Ptd -- B ): leaves Boolean for whether Path to directory
       is empty. Dies if Path to directory points to something
       other than a directory, or doesn't exist.
      END
      ) do |engine, stack|
        path = stack.drop.a(Quote)

        unless boolean = dir_empty?(engine, path)
          path.die("no directory at path")
        end

        boolean.onto(stack)
      end

      target.at("disk:join", <<-END
      ( Bp Cp -- P ): leaves Path, which is the result of joining Base
       path and Child path using the platform-specific path separator.

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
      ( -- Wd ): leaves current Working directory.
      END
      ) do |engine, stack|
        pwd(engine).onto(stack)
      end

      target.at("disk:touch", <<-END
      ( P -- ): creates an empty file at Path. Does nothing
       if Path already exists.
      END
      ) do |engine, stack|
        path = stack.drop.a(Quote)
        touch(engine, path)
      end

      target.at("disk:mkdir", <<-END
      ( P -- ): creates an empty directory at Path, including
       any non-existing intermediate directories. Does nothing
       if Path already exists.
      END
      ) do |engine, stack|
        path = stack.drop.a(Quote)
        mkdir(engine, path)
      end

      target.at("disk:copy", <<-END
      ( S D -- ): copies Source (quote path to a file, symlink,
       or directory) to Destination (also a quote).

      If Source is a directory, copies it recursively.
      If copy process failed, dies.
      END
      ) do |engine, stack|
        dst = stack.drop.a(Quote)
        src = stack.drop.a(Quote)
        unless copy(engine, src, dst)
          src.die("could not copy")
        end
      end

      target.at("disk:read", <<-END
      ( F -- C ): reads and leaves the Contents of File. Dies
       if there is no File.
      END
      ) do |engine, stack|
        path = stack.drop.a(Quote)
        path.die("no file at path") unless contents = read?(engine, path)
        contents.onto(stack)
      end

      target.at("disk:write", <<-END
      ( Cq/B Fp -- ): (over)writes content of file at File path
       with Content quote/Byteslice. Dies if File path doesn't
       exist or doesn't point to a file.
      END
      ) do |engine, stack|
        path = stack.drop.a(Quote)
        content = stack.drop.a(Quote | Byteslice)
        path.die("no file at path") unless write?(engine, content, path)
      end
    end
  end
end
