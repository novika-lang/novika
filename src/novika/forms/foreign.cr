module Novika
  struct ForeignFunction
    include Form

    def initialize(@library : Library, @function : FFI::Function, @comment : String?)
    end

    def on_open(engine : Engine) : self
      stack = engine.stack

      if @function.arity.zero?
        value = @function.call
      else
        args = [] of FFI::ForeignValue
        (0...@function.arity).reverse_each do |index|
          argtype = @function.argtypes[index]
          args.unshift argtype.from(stack.drop)
        end
        value = @function.call(args)
      end

      value.to_form?.try &.onto(stack)

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

    delegate :address, to: @handle

    def initialize(pointer : FFI::UntypedPointer)
      @handle = pointer.box
      @type = FFI::UntypedPointer
    end

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

  class StructLayoutForm
    include Form

    @this : Block?
    @names : Array(Word)?
    @types : Array(Word)?

    def initialize(@this : Block, @names : Array(Word), @types : Array(Word))
      @layout = Novika::FFI::StructLayout.new
      @finished = false
    end

    def initialize(@layout)
      @finished = true
    end

    def layout(parent_object_ids = nil)
      return @layout if @finished || (parent_object_ids && object_id.in?(parent_object_ids))
      return @layout unless this = @this
      return @layout unless names = @names
      return @layout unless types = @types

      types = types.map do |typename|
        case typename.id
        when "u8"      then {false, typename, FFI::U8}
        when "u16"     then {false, typename, FFI::U16}
        when "u32"     then {false, typename, FFI::U32}
        when "u64"     then {false, typename, FFI::U64}
        when "i8"      then {false, typename, FFI::I8}
        when "i16"     then {false, typename, FFI::I16}
        when "i32"     then {false, typename, FFI::I32}
        when "i64"     then {false, typename, FFI::I64}
        when "f32"     then {false, typename, FFI::F32}
        when "f64"     then {false, typename, FFI::F64}
        when "none"    then {false, typename, FFI::None}
        when "cstr"    then {false, typename, FFI::Cstr}
        when "nothing" then {false, typename, FFI::Nothing}
        when "pointer" then {false, typename, FFI::UntypedPointer}
        else
          unless (inline = typename.id.prefixed_by?('~')) || typename.id.prefixed_by?('&')
            typename.die(
              "could not recognize foreign type. Did you mean `~#{typename}` \
               (inline struct) or `&#{typename}` (reference to struct)?")
          end

          typename = Word.new(typename.id.lchop)
          form = this.form_for(typename)
          unless form.as?(StructLayoutForm)
            typename.die("expected struct layout to be value form, not: #{form.class.typedesc}")
          end
          form = form.as(StructLayoutForm)

          {inline, typename, form}
        end
      end

      names.zip(types) do |name, (inline, typename, type)|
        if type.is_a?(StructLayoutForm)
          parent_object_ids ||= Set(UInt64).new
          parent_object_ids << object_id
          if inline && parent_object_ids && type.object_id.in?(parent_object_ids)
            typename.die("inline struct cycle detected: consider using struct reference (#{name} ~#{typename})")
          end
          l = type.layout(parent_object_ids)
          ffi_type = inline ? l.inline : l.reference
        else
          ffi_type = type
        end
        @layout.add(name.id, ffi_type)
      end

      @finished = true

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

        argforms = [] of Word
        retforms = [] of Word
        half = argforms

        (1...fdecl.count).each do |index|
          form = fdecl.at(index)

          unless form.is_a?(Word)
            form.die("expected type in function declaration to be a word")
          end

          if form.id == "--"
            half = retforms
            next
          end

          half << form
        end

        unless retforms.size == 1
          fdecl.die(
            "function declaration must always contain `--` followed by exactly \
             one return type. If function returns void, write: `-- nothing`")
        end

        argtypes = argforms.map do |argform|
          FFI::ForeignType
            .parse(this, argform)
            .as(FFI::ForeignType)
        end

        return_type = FFI::ForeignType.parse(this, retforms.first)

        # A hell of an abstraction leak huh?.. This whole piece
        # of dung is, really.
        unless sym = LibC.dlsym(@handle, foreign_name.id)
          message = String.new(LibC.dlerror)
          message = message.lstrip("#{@path.expand}: ")
          fdecl.die("malformed function declaration: #{message}")
        end

        function = FFI::Function.new(foreign_name.id, sym, argtypes, return_type)
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
