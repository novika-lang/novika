require "big"
require "colorize"
require "file_utils"

# Order is important!
require "./novika/forms/form"
require "./novika/tape"
require "./novika/table"
require "./novika/forms/*"
require "./novika/world"
require "./novika/primitives"

def help : NoReturn
  cdir = "directory".colorize.blue
  cfile = "file".colorize.green

  abort <<-END
  Welcome to Novika, and thanks for trying it out!

  One or more arguments must be provided for Novika to properly
  pick up what you're trying to run. For instance:

    $ novika     core             example.nk
                 ----             ----------
                 a #{cdir}        a #{cfile}

  (1) When you provide a #{cdir}, Novika will run all *.nk
      files in that directory. First, *.nk files in the directory
      itself are run, and then that process is repeated in the
      sub-directories. For any given directory, the main file
      in that directory is dirname.nk. It is always run first.

  (2) In other words, a #{cdir} provided in arguments has higher
      priority than a #{cfile}. But then, files in those directories
      have higher priority than sub-directories.

  You can try running the following command:

    $ novika core hello.nk

  END
end

record Mod, entry : Path? = nil, files = [] of Path do
  def add(file)
    files << file
  end
end

# Collects files and directories as stated in `help`, starting
# at *root*, and saves them in *mods*.
def collect(mods, root : Path)
  if File.file?(entry = root / "#{root.stem}.nk")
    mods[root] = mod = Mod.new(entry)
  else
    mods[root] = mod = Mod.new
  end

  Dir.glob(root / "*.nk") do |path|
    path = Path[path]
    mod.add(path) unless path == entry
  end

  Dir.glob(root / "/*/") do |path|
    collect(mods, Path[path])
  end
end

def import(recpt : Novika::Block, donor : Novika::Block)
  donor.ls.each do |name|
    unless name.is_a?(Novika::Word) && name.id.prefixed_by?('_')
      recpt.at name, donor.at(name)
    end
  end
end

def run(world, toplevel, path : Path)
  {% unless flag?(:release) %}
    puts path.colorize.dark_gray
  {% end %}
  source = File.read(path)
  stack = Novika::Block.new
  block = Novika::Block.new(toplevel).slurp(source)
  world.conts.add Novika::World.cont(block.to(0), stack)
  world.exhaust
  import(toplevel, block)
end

help if ARGV.empty?

cwd = Path[FileUtils.pwd]

dirs = [] of Path
files = [] of Path

ARGV.each do |arg|
  case File
  when .directory?(arg) then dirs << Path[arg]
  when .file?(arg)      then files << Path[arg]
  else
    abort "#{arg.colorize.bold} is neither a file nor a directory avaliable in #{cwd.to_s}"
  end
end

mods = {} of Path => Mod

dirs.each do |path|
  collect(mods, Path[path])
end

world = Novika::World.new
prims = Novika::Block.new
Novika::Primitives.inject(into: prims)
toplevel = Novika::Block.new(prims)

# Evaluate module entries fisrt, if any.
mods.each_value.select(&.entry).each do |mod|
  run(world, toplevel, mod.entry.not_nil!)
end

# Then evaluate all other files.
mods.each_value do |mod|
  mod.files.each do |file|
    run(world, toplevel, file)
  end
end

# Then evalute user's files.
files.each do |file|
  run(world, toplevel, file)
end
