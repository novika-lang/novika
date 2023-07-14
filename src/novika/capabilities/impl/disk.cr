require "file_utils"

module Novika::Capabilities::Impl
  class Disk < IDisk
    def can_read?(engine, path : Quote) : Boolean
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

    def dir_empty?(engine, path : Quote) : Boolean?
      Boolean[Dir.empty?(path.string)] if File.directory?(path.string)
    end

    def join(engine, base : Quote, child : Quote) : Quote
      Quote.new(File.join(base.string, child.string))
    end

    def pwd(engine) : Quote
      Quote.new(Dir.current)
    end

    def home(engine) : Quote
      Quote.new(Path.home.to_s)
    end

    def touch(engine, path : Quote)
      File.touch(path.string)
    end

    def mkdir(engine, path : Quote)
      return if File.exists?(path.string)

      FileUtils.mkdir_p(path.string)
    end

    def copy(engine, src : Quote, dst : Quote) : Bool
      return false unless File.exists?(src.string)

      FileUtils.cp_r(src.string, dst.string)

      true
    end

    def read?(engine, path : Quote) : Quote?
      Quote.new(File.read(path.string)) if File.file?(path.string)
    end

    def write?(engine, content : Quote, path : Quote) : Bool
      unless File.file?(path.string) && File.writable?(path.string)
        return false
      end
      File.write(path.string, content.string)
      true
    end

    def write?(engine, content : Byteslice, path : Quote) : Bool
      return false unless File.file?(path.string) && File.writable?(path.string)

      File.open(path.string, "wb") do |handle|
        content.write_to(handle)
      end

      true
    end
  end
end
