module Novika
  struct ForeignFunction
    include Form

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
      io << "[foreign function " << @function.id << "]"
    end
  end

  struct Hole
    include Form

    getter handle : Void*

    def initialize(@type : FFI::ForeignType)
      @handle = @type.alloc
    end

    def initialize(pointer : FFI::UntypedPointer)
      @handle = pointer.box
      @type = FFI::UntypedPointer
    end

    delegate :address, to: @handle

    def on_open(engine : Engine) : self
      @type.unbox(@handle).to_form?.try &.onto(engine.stack)

      self
    end

    def self.typedesc
      "hole"
    end

    def desc(io)
      to_s(io)
    end

    def to_s(io)
      io << "[" << @type << " @ 0x"
      address.to_s(io, base: 16)
      io << "]"
    end
  end

  class StructViewForm
    include Form
    include IReadableStore
    include ISubmittableStore

    getter view

    def initialize(@view : FFI::StructView)
    end

    delegate :address, to: view

    def layout : StructLayoutForm
      StructLayoutForm.new(view.@layout)
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

      @view.@layout.desc?(name.id).try do |desc|
        @view[name.id] = desc.type.from(form)
      end
    end

    def opens?(name : Form)
      false
    end

    def pushes?(name : Form)
      has_form_for?(name)
    end

    def desc(io)
      to_s(io)
    end

    def ==(other : StructViewForm)
      return true if same?(other)
      return false unless @view.size == other.@view.size
      result = false
      executed = exec_recursive(:==) do
        result = @view == other.@view
      end
      executed && result
    end

    def to_s(io)
      io << @view
    end
  end

  struct StructLayoutParser < FFI::TypeParser
    include FFI::TypeParser::ForbidsNothing

    def initialize(this, typename, @field : Word, @current : StructLayoutForm, @outerset : Set(UInt64)? = nil)
      super(this, typename)
    end

    # Appends the current layout's object id to the outer set of ids.
    # This is normally done to prevent/detect (deep) self-reference.
    #
    # Returns the outerset.
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
         type (pointer or &#{@typename.id.lchop}) for '#{@field}'")
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

  class StructLayoutForm
    include Form

    @this : Block?
    @names : Array(Word)?
    @types : Array(Word)?

    def initialize(@this : Block, @names : Array(Word), @types : Array(Word))
      @layout = Novika::FFI::StructLayout.new
      @sealed = false
    end

    def initialize(@layout)
      @sealed = true
    end

    def layout(outerset = nil)
      return @layout if @sealed || outerset.try &.includes?(object_id)
      return @layout unless this = @this
      return @layout unless names = @names
      return @layout unless types = @types

      names.zip(types) do |name, typename|
        type = StructLayoutParser.new(@this, typename, name, self, outerset).parse
        @layout.add(name.id, type)
      end

      @sealed = true
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
  class Library
    include Form

    # Returns the identifier of this library.
    getter id : String

    private def initialize(@id, @path : Path, @handle : Void*)
    end

    def finalize
      LibC.dlclose(@handle)
    end

    # Initializes a library for a dynamic library found at *path*,
    # with the given *id*entifier (may be chosen arbitrarily).
    #
    # May die if LibDL fails to load the library.
    def self.new(id : String, path : Path)
      unless handle = LibC.dlopen(path.to_s, LibC::RTLD_NOW)
        raise Error.new(String.new(LibC.dlerror))
      end

      new(id, path, handle)
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
      fname.die("function name must be a word or alias block `[ foreign-name opener-name ]`")
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
              var_args = [] of FFI::ForeignType
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
          "function declaration must always contain `--` followed \
           by exactly one return type. If function returns void, \
           use `-- nothing`")
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
      unless sym = LibC.dlsym(@handle, foreign_name.id)
        message = String.new(LibC.dlerror)
        message = message.lstrip("#{@path.expand}: ")
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
      "library"
    end

    def desc(io)
      to_s(io)
    end

    def to_s(io)
      io << "[library " << id << "]"
    end
  end
end
