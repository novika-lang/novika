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

  class Library
    include Form

    getter id : String

    private def initialize(@id, @path : Path, @handle : Void*)
    end

    def finalize
      LibC.dlclose(@handle)
    end

    def self.new(id, path : Path)
      unless handle = LibC.dlopen(path.to_s, LibC::RTLD_NOW)
        raise Error.new(String.new(LibC.dlerror))
      end

      new(id, path, handle)
    end

    def on_open(engine : Engine) : self
      this = engine.block

      fdecls = engine.stack.drop.a(Block)
      fdecls.each do |fdecl|
        fdecl = fdecl.a(Block)

        unless name = fdecl.at?(0)
          fdecl.die("first form in function declaration must be the function's name")
        end

        case name
        when Word
          opener_name = name
          foreign_name = name
        when Block
          unless name.count == 2
            name.die("malformed alias block: expected foreign name followed by opener name")
          end

          opener_name = name.at(1).a(Word)
          foreign_name = name.at(0).a(Word)
        else
          name.die("function name must be a word or alias block `[ foreign-name opener-name ]`")
        end

        argforms = [] of Word | Block
        retforms = [] of Word | Block
        half = argforms

        # Stuff everything to the left of '--' to argforms array and
        # everything to the right to retforms array.
        (1...fdecl.count).each do |index|
          form = fdecl.at(index).a(Word | Block)

          if form.is_a?(Word) && form.id == "--"
            half = retforms
            next
          end

          half << form
        end
        argtypes = [] of FFI::ForeignType
        va_args = nil

        argforms.each_with_index do |argform, index|
          if argform.is_a?(Block) && index != argforms.size - 1
            argform.die("only one varargs block is allowed, and must be positioned last in function declaration")
          end

          if argform.is_a?(Block)
            va_args = [] of FFI::ForeignType
            argform.each do |form|
              va_args << FFI::ValueTypeParser.new(this, form.a(Word)).parse
            end
            next
          end

          argtypes << FFI::ValueTypeParser.new(this, argform.a(Word)).parse
        end

        if va_args && argtypes.empty?
          fdecl.die("function declaration must have at least one fixed argument other than varargs")
        end

        unless retforms.size == 1
          fdecl.die(
            "function declaration must always contain `--` followed by exactly \
             one return type. If function returns void, write: `-- nothing`")
        end

        unless (return_form = retforms.first).is_a?(Word)
          return_form.die("cannot use varargs as return type")
        end

        return_type = FFI::DefaultTypeParser.new(this, return_form).parse

        # A hell of an abstraction leak huh?.. This whole piece
        # of dung is, really.
        unless sym = LibC.dlsym(@handle, foreign_name.id)
          message = String.new(LibC.dlerror)
          message = message.lstrip("#{@path.expand}: ")
          fdecl.die("malformed function declaration: #{message}")
        end

        if va_args
          function = FFI::VariadicFunction.new(foreign_name.id, sym, argtypes, va_args, return_type)
        else
          function = FFI::FixedArityFunction.new(foreign_name.id, sym, argtypes, return_type)
        end
        invoker = ForeignFunction.new(self, function, fdecl.prototype.comment?)

        this.at(opener_name, OpenEntry.new(invoker))
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
