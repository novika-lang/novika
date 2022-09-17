module Novika::Features
  abstract class IDisk
    include Feature

    def self.id : String
      "disk"
    end

    def self.purpose : String
      "exposes various disk-related (storage-related) words"
    end

    def self.on_by_default? : Bool
      true
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

    # Creates an empty file at *path*. Does nothing if *path*
    # already exists.
    abstract def touch(engine, path : Quote)

    # Reads and returns the contents of file at *path*. Returns
    # nil if there is no file at *path*.
    abstract def read?(engine, path : Quote) : Quote?

    def inject(into target : Block)
      target.at("disk:has?", <<-END
      ( Pq -- true/false ): leaves whether Path quote exists
       on the disk.
      END
      ) do |engine|
        path = engine.stack.drop.assert(engine, Quote)
        has?(engine, path).push(engine)
      end

      target.at("disk:canRead?", <<-END
      ( Pq -- true/false ): leaves whether Path quote exists
       and is readable.
      END
      ) do |engine|
        path = engine.stack.drop.assert(engine, Quote)
        can_read?(engine, path).push(engine)
      end

      target.at("disk:hasDir?", <<-END
      ( Pq -- true/false ): leaves whether Path quote exists
       and points to a directory.
      END
      ) do |engine|
        path = engine.stack.drop.assert(engine, Quote)
        has_dir?(engine, path).push(engine)
      end

      target.at("disk:hasFile?", <<-END
      ( Pq -- true/false ): leaves whether Path quote exists
       and points to a file.
      END
      ) do |engine|
        path = engine.stack.drop.assert(engine, Quote)
        has_file?(engine, path).push(engine)
      end

      target.at("disk:hasSymlink?", <<-END
      ( Pq -- true/false ): leaves whether Path quote exists
       and points to a symlink.
      END
      ) do |engine|
        path = engine.stack.drop.assert(engine, Quote)
        has_symlink?(engine, path).push(engine)
      end

      target.at("disk:touch", <<-END
      ( P -- ): creates an empty file at Path. Does nothing
       if Path already exists.
      END
      ) do |engine|
        path = engine.stack.drop.assert(engine, Quote)
        touch(engine, path)
      end

      target.at("disk:read", <<-END
      ( F -- C ): reads and leaves the Contents of File. Dies
       if there is no File.
      END
      ) do |engine|
        path = engine.stack.drop.assert(engine, Quote)
        path.die("no file at path") unless contents = read?(engine, path)
        contents.push(engine)
      end
    end
  end
end
