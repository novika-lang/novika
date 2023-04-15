require "compiler/crystal/loader"

module Novika
  # A thin wrapper around `FFI::Function`.
  struct ForeignFunction
    include Form
    include ShouldOpenWhenScheduled

    def initialize(@library : Library, @function : FFI::Function, @comment : String?)
    end

    def on_open(engine : Engine) : self
      stack = engine.stack

      value = @function.call(stack)
      value.try &.onto(stack)

      self
    end

    def self.typedesc
      "foreign function"
    end

    def desc(io)
      @comment ? io << @comment : to_s(io)
    end

    def to_s(io)
      io << "[foreign function: " << @function.id << "]"
    end
  end

  # Holes are similar to Crystal's `uninitialized` or `out`, in that
  # they allow you to allocate memory for a type, pass a pointer to
  # that memory to e.g. a C function, and let that C function write
  # into the memory. The written value can then be retrieved by
  # opening the hole.
  struct Hole
    include Form
    include ShouldOpenWhenScheduled

    # Returns a pointer to this hole's content.
    getter handle : Void*

    def initialize(@type : FFI::ForeignType)
      @handle = @type.alloc
    end

    def initialize(pointer : FFI::UntypedPointer)
      @handle = pointer.box
      @type = FFI::UntypedPointer
    end

    # Returns the address of this hole's content in memory.
    delegate :address, to: @handle

    def on_open(engine : Engine) : self
      form = @type.unbox(@handle).to_form?
      form.try &.onto(engine.stack)

      self
    end

    def self.typedesc
      "hole"
    end

    def desc(io)
      to_s(io)
    end

    def to_s(io)
      io << "[" << @type << " hole: 0x"
      address.to_s(io, base: 16)
      io << "]"
    end
  end

  # A thin wrapper around `FFI::StructView` and its descendants.
  #
  # This form is a readable and submittable store, which means you
  # can read (e.g. `entry:fetch`) and submit (e.g. `entry:submit`)
  # to exsisting entries.
  struct StructViewForm
    include Form
    include IReadableStore
    include ISubmittableStore

    # Returns the underlying struct view.
    getter view : FFI::StructView

    def initialize(@view)
    end

    # Returns the address of the underlying struct in memory.
    delegate :address, to: view

    # Returns the struct layout of the underlying struct view.
    def layout : StructLayoutForm
      StructLayoutForm.new(view.layout)
    end

    def self.typedesc
      "foreign struct view"
    end

    def has_form_for?(name : Form) : Bool
      name.is_a?(Word) ? @view.has_field?(name.id) : false
    end

    def form_for?(name : Form) : Form?
      @view[name.id]?.try &.to_form? if name.is_a?(Word)
    end

    def submit?(name : Form, form : Form)
      return unless name.is_a?(Word)

      @view.layout.desc?(name.id).try do |desc|
        @view[name.id] = desc.type.from(form)
      end
    end

    def opens?(name : Form)
      false
    end

    def pushes?(name : Form)
      has_form_for?(name)
    end

    # Returns whether this view is a struct reference view.
    def reference?
      view.is_a?(FFI::StructReferenceView)
    end

    # Returns whether this view is an inline struct view.
    def inline?
      view.is_a?(FFI::InlineStructView)
    end

    # Returns whether this view is a union view.
    def union?
      view.is_a?(FFI::UnionView)
    end

    def desc(io)
      to_s(io)
    end

    def to_s(io)
      io << @view
    end

    # Returns whether this and *other* struct views are equal.
    # Performs deep, recursive equality based on the fields'
    # values. Supports self-reference, mutual reference, etc.
    def_equals @view
  end

  # Parses types in struct layouts. Similar to `FFI::ValueTypeParser`,
  # but does some bookkeeping to stay away from deep recursion/ensure
  # no cycles exist for inline structs/unions.
  struct StructLayoutParser < FFI::TypeParser
    include FFI::TypeParser::ForbidsNothing

    def initialize(this, typename, @field : Word, @current : StructLayoutForm, @outerset : Set(UInt64)? = nil)
      super(this, typename)
    end

    # Appends the current layout's object id to the outer set of ids.
    # This is normally done to prevent/detect (deep) self-reference.
    #
    # Returns the outerset.
    #
    # ┌────────────────────────┐
    # │ ID1                    │
    # │                        │
    # │  ┌──────────────────┐  │
    # │  │ ID2              │  │
    # │  │                  │  │
    # │  │                  │  │
    # │  │   ┌───────────┐  │  │
    # │  │   │ ID3       │  │  │
    # │  │   │           │  │  │  Outerset: ID1 ID2 ID3
    # │  │   │     ◄─────┼──┼──┼─────
    # │  │   │           │  │  │
    # │  │   │  current  │  │  │
    # │  │   └───────────┘  │  │
    # │  │                  │  │
    # │  └──────────────────┘  │
    # │                        │
    # └────────────────────────┘
    private def add_to_outerset : Set(UInt64)
      outerset = @outerset ||= Set(UInt64).new
      outerset << @current.object_id
    end

    # Dies if *form*'s id is in the outer (as in nesting) set
    # of ids. Otherwise, adds *form*'s id to the outer set.
    private def check_cycles(form)
      return unless add_to_outerset.includes?(form.object_id)

      @typename.die(
        "inline struct cycle detected: consider using reference \
         type (⸢pointer⸥ or ⸢&#{@typename.id.lchop}⸥) for '#{@field}'")
    end

    def on_union(form : StructLayoutForm) : FFI::ForeignType
      check_cycles(form)

      form.layout(@outerset).union
    end

    def on_inline_struct(form : StructLayoutForm) : FFI::ForeignType
      check_cycles(form)

      form.layout(@outerset).inline
    end

    def on_struct_reference(form : StructLayoutForm) : FFI::ForeignType
      add_to_outerset

      form.layout(@outerset).reference
    end
  end

  # A thin form wrapper around `FFI::StructLayout`. Lazily parses
  # a struct layout definition and keeps the corresponding
  # `FFI::StructLayout` in sync.
  struct StructLayoutForm
    include Form

    @this : Block?
    @names : Array(Word)?
    @types : Array(Word)?

    # Initializes a struct layout form. Names array *names* must
    # be created uniquely for this form, because it will be used
    # as this struct layout form's identity during deep recursion
    # checks etc.
    #
    # *this* block is going to be used for lookup of user-defined
    # struct layouts (e.g. `&foobar`).
    def initialize(@this : Block, @names : Array(Word), @types : Array(Word))
      @layout = FFI::StructLayout.new
    end

    # Initializes a struct layout form from the given *layout*.
    # The layout must contain at least one field.
    def initialize(@layout)
      if @layout.field_count.zero?
        raise "BUG: bad layout passed to StructLayoutForm"
      end
    end

    # Since `StructLayoutForm` is a struct, it doesn't have its own
    # object id, and instead borrows it from the names array, which
    # is assumed to be created personally for this struct layout form.
    delegate :object_id, to: (@names || raise "BUG: bad state")

    # Returns the underlying layout.
    def layout(outerset = nil)
      return @layout if @layout.field_count > 0 || outerset.try &.includes?(object_id)
      return @layout unless this = @this
      return @layout unless names = @names
      return @layout unless types = @types

      names.zip(types) do |name, typename|
        parser = StructLayoutParser.new(@this, typename, name, self, outerset)

        @layout.add(name.id, parser.parse)
      end

      @layout
    end

    def self.typedesc
      "foreign struct layout"
    end

    def desc(io)
      to_s(io)
    end

    def to_s(io)
      io << layout
    end

    def_equals layout
  end

  # A library is a collection of foreign functions.
  #
  # A library form can be opened with a block of *function declarations*
  # to be exposed. Each function declaration consists of the function's
  # name and type signature. Exposed functions are then defined in the
  # opener block.
  #
  # For more details, see Novika's `ffi:getLibrary`.
  #
  # Internally, library objects are created by the frontend and fed
  # to the capability collection `caps`. When needed, they are
  # retrieved from this capability collection.
  class Library
    include Form
    include ShouldOpenWhenScheduled

    # Returns the identifier of this library.
    getter id : String

    private def initialize(@id, @path : Path, @handle : Void*)
    end

    def finalize
      LibDl.dlclose(@handle)
    end

    # Tries to find the library with the given *id* in the
    # system-specific library directories and in the current
    # working directory.
    #
    # Returns nil if the library could not be found / loaded.
    def self.new?(id : String, resolver : RunnableResolver) : Library?
      candidates = [] of String

      {% if flag?(:windows) %}
        candidates << "#{id}.dll"
        candidates << "lib#{id}.dll"
      {% elsif flag?(:darwin) %}
        candidates << "#{id}.dylib"
        candidates << "lib#{id}.dylib"
      {% elsif flag?(:unix) %}
        candidates << "#{id}.so"
        candidates << "lib#{id}.so"
      {% else %}
        return
      {% end %}

      Crystal::Loader.default_search_paths.each do |search_path|
        # ???
        #
        # https://github.com/crystal-lang/crystal/blob/42a3f91335852613824a6a2587da6e590b540518/src/compiler/crystal/loader/msvc.cr#L65

        candidates.each do |candidate|
          if library = Library.new?(id, Path[search_path] / candidate)
            return library
          end
        end
      end

      # If not in search paths or no search paths, try looking
      # in Novika-specific directories.
      candidates.each do |candidate|
        next unless path = resolver.expand_runnable_path?(Path[candidate])
        next unless library = Library.new?(id, path)
        return library
      end
    end

    # Initializes a library for the dynamic library at *path*,
    # with the given *id*entifier (it may be chosen arbitrarily).
    #
    # Returns nil if the library could not be loaded.
    def self.new?(id : String, path : Path) : Library?
      return unless handle = LibDl.dlopen(path.to_s, LibDl::RTLD_NOW)

      new(id, path, handle)
    end

    # Initializes a library for the dynamic library at *path*,
    # with the given *id*entifier (may be chosen arbitrarily).
    #
    # May die if LibDL fails to load the library.
    def self.new(id : String, path : Path) : Library
      new?(id, path) || raise Error.new(String.new(LibDl.dlerror))
    end

    # Parses function name or alias block *fname*.
    #
    # Returns a tuple of {foreign name, opener name}. Dies if
    # could not parse.
    private def parse_fn_name(fname : Word)
      {fname, fname}
    end

    # :ditto:
    private def parse_fn_name(fname : Block)
      unless fname.count == 2
        fname.die("malformed alias block: expected foreign name followed by opener name")
      end

      {fname.at(0).a(Word), fname.at(1).a(Word)}
    end

    # :ditto:
    private def parse_fn_name(fname)
      fname.die("function name must be a word or alias block ⸢[ foreign-name opener-name ]⸥")
    end

    # Parses function head (arguments and return type) in function
    # declaration *fdecl*, starting at the given *start* index.
    #
    # *this* block is used to resolve argument/return types.
    #
    # Returns a tuple of the following form:
    #
    # `{return type, fixed argument types, vararg allowed types?}`
    private def parse_fn_signature(this : Block, fdecl : Block, start : Int)
      var_args = nil
      fixed_args = [] of FFI::ForeignType
      return_type = nil

      # It's at least:
      #
      #   -- <return type word>
      #
      # Otherwise, it's invalid anyway.
      if fdecl.count - start >= 2
        hi = fdecl.count

        (start...hi).each do |index|
          cur = fdecl.at(index)

          case index
          when ...hi - 3
            #
            #  W1 W2 W3 W4 [ ... ] -- W5
            #  ^^^^^^^^^^^
            #
            fixed_args << FFI::ValueTypeParser.new(this, cur.a(Word)).parse
          when hi - 3
            # Last argument must be a word or a block.
            cur = cur.a(Word | Block)
            if cur.is_a?(Word)
              # If it is a word, then it's simply the last argument.
              #
              #  W1 W2 W3 W4 W5 -- W6
              #              ^^
              #
              fixed_args << FFI::ValueTypeParser.new(this, cur).parse
            elsif cur.is_a?(Block)
              # If it is a block, then it's the varargs block.
              #
              #  W1 W2 W3 W4 [ ... ] -- W5
              #              ^^^^^^^
              #
              var_args = Array(FFI::ForeignType).new(cur.count)
              cur.each do |typename|
                var_args << FFI::ValueTypeParser.new(this, typename.a(Word)).parse
              end
            end
          when hi - 2
            #
            #  W1 W2 W3 W4 [ ... ] -- W5
            #                      ^^
            #
            # By breaking here, we leave return type equal to nil,
            # therefore, the error clause below will trigger.
            break unless cur.is_a?(Word) && cur.id == "--"
          when hi - 1
            #
            #  W1 W2 W3 W4 [ ... ] -- W5
            #                         ^^
            #
            return_type = FFI::DefaultTypeParser.new(this, cur.a(Word)).parse
          end
        end
      end

      unless return_type
        fdecl.die(
          "function declaration must always contain ⸢--⸥ followed \
           by exactly one return type. If function returns void, \
           use ⸢-- nothing⸥")
      end

      # C varargs require at least one fixed argument.
      if var_args && fixed_args.empty?
        fdecl.die("function declaration must have at least one fixed argument other than varargs")
      end

      {return_type, fixed_args, var_args}
    end

    # Parses a single function declaration, and defines the
    # corresponding entry in *this*.
    private def parse_fdecl(this : Block, fdecl : Block)
      unless fname = fdecl.at?(0)
        fdecl.die("first form in function declaration must be the function's name")
      end

      foreign_name, opener_name = parse_fn_name(fname)
      return_type, fixed_args, var_args = parse_fn_signature(this, fdecl, start: 1)

      # A hell of an abstraction leak huh? This whole piece of dung
      # is, really.
      unless sym = LibDl.dlsym(@handle, foreign_name.id)
        message = String.new(LibDl.dlerror)
        message = message.lchop("#{@path.expand}: ")
        fdecl.die("malformed function declaration: #{message}")
      end

      if var_args
        ffi_fn = FFI::VariadicFunction.new(foreign_name.id, sym, fixed_args, var_args, return_type)
      else
        ffi_fn = FFI::FixedArityFunction.new(foreign_name.id, sym, fixed_args, return_type)
      end

      # Note how we use prototype's comment. This is similar to how
      # blocks work: they "inherit" their doc comment from their prototype.
      fn = ForeignFunction.new(self, ffi_fn, fdecl.prototype.comment?)

      this.at(opener_name, OpenEntry.new(fn))
    end

    def on_open(engine : Engine) : self
      this = engine.block

      fdecls = engine.stack.drop.a(Block)
      fdecls.each do |fdecl|
        parse_fdecl(this, fdecl.a(Block))
      end

      self
    end

    def self.typedesc
      "foreign library"
    end

    def desc(io)
      to_s(io)
    end

    def to_s(io)
      io << "[foreign library: " << id << "]"
    end
  end
end
