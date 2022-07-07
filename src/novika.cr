require "big"
require "colorize"
require "file_utils"

# Order is important!
require "./novika/forms/form"
require "./novika/tape"
require "./novika/table"
require "./novika/forms/*"
require "./novika/world"
require "./novika/package"
require "./novika/packages/*"

def help : NoReturn
  cdir = "directory".colorize.blue
  cpkg = "package".colorize.magenta
  cfile = "file".colorize.green
  on = "on by default".colorize.bold

  abort <<-END
  Welcome to Novika, and thanks for trying it out!

  One or more arguments must be provided for Novika to properly
  pick up what you're trying to run. For instance:

    $ novika     core          console      example.nk
                 ----          -------      ----------
                 a #{cdir}   a #{cpkg}    a #{cfile}

  (1) When you provide a #{cdir}, Novika will run all *.nk
      files in that directory. First, *.nk files in the directory
      itself are run, and then that process is repeated in the
      sub-directories. For any given directory, the main file
      in that directory is dirname.nk. It is always run first.

  (2) Individual #{cfile}s are run after all directories are run.

  (3) There are also a number of builtin #{cpkg}s:
        - kernel (#{on})
        - math (#{on})
        - console (enables the console API)
  END

  # TODO: autogenerate (3)
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

def run(world, toplevel, path : Path)
  {% unless flag?(:release) %}
    puts path.colorize.dark_gray
  {% end %}
  source = File.read(path)
  stack = Novika::Block.new
  block = Novika::Block.new(toplevel).slurp(source)
  world.conts.add Novika::World.cont(block.to(0), stack)
  world.exhaust
  toplevel.merge_table!(with: block)
end

help if ARGV.empty?

cwd = Path[FileUtils.pwd]

dirs = [] of Path
files = [] of Path
pkgs = [] of Novika::Package
pkgs << Novika::Packages::Kernel.new
pkgs << Novika::Packages::Math.new

ARGV.each do |arg|
  if pkg = Novika::Package[arg]?
    pkgs << pkg.new unless pkgs.any?(pkg)
    next
  end

  case File
  when .directory?(arg) then dirs << Path[arg]
  when .file?(arg)      then files << Path[arg]
  else
    abort "#{arg.colorize.bold} is not a file, directory, or package avaliable in #{cwd.to_s}"
  end
end

mods = {} of Path => Mod

dirs.each do |path|
  collect(mods, Path[path])
end

world = Novika::World.new
pkgblock = Novika::Block.new
toplevel = Novika::Block.new(pkgblock)

pkgs.each do |pkg|
  pkg.inject(into: pkgblock)
end

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
