{% if flag?(:windows) %}
  @[Link(ldflags: "\"/LIBPATH:#{__DIR__}\" dl.lib")]
  lib LibDl
    RTLD_NOW = 0

    fun dlopen(file : UInt8*, mode : LibC::Int) : Void*
    fun dlclose(handle : Void*) : LibC::Int
    fun dlsym(handle : Void*, name : UInt8*) : Void*
    fun dlerror : UInt8*
  end
{% else %}
  alias LibDl = LibC
{% end %}
