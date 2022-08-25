module Novika::Packages
  class Disk < IDisk
    def readable?(engine, path : Quote) : Boolean
      Boolean[File.readable?(path.string)]
    end

    def has?(engine, path : Quote) : Boolean
      Boolean[File.exists?(path.string)]
    end

    def has_file?(engine, path : Quote) : Boolean
      Boolean[File.file?(path.string)]
    end

    def has_dir?(engine, path : Quote) : Boolean
      Boolean[Dir.exists?(path.string)]
    end

    def has_symlink?(engine, path : Quote) : Boolean
      Boolean[File.symlink?(path.string)]
    end

    def touch(engine, path : Quote)
      File.touch(path.string)
    end

    def read?(engine, path : Quote) : Quote?
      Quote.new(File.read(path.string)) if File.file?(path.string)
    end
  end
end
