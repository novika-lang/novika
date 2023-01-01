require "compiler/crystal/ffi"

module Novika::FFI
  # Base type for Novika FFI values (both heap & stack allocated).
  module ForeignValue
    # Wraps this value in a void pointer.
    abstract def box : Void*

    # Writes this value starting at the given *base* pointer.
    abstract def write_to!(base : Void*)

    # Determines the best form type to represent this foreign
    # value, then builds and returns a form of that type.
    #
    # Returns nil if *value* is nothing.
    abstract def to_form? : Form?

    # Raises if this value is not of the given `ForeignType` *type*.
    def must_be_of(type : ForeignType)
      return if type.matches?(self)

      raise Error.new("#{type} is incompatible with #{self}")
    end
  end

  # Base type for Novika FFI types.
  module ForeignType
    # Allocates memory for this type. Returns a pointer to that memory.
    abstract def alloc : Void*

    # Retrieves `ForeignValue` of this type from the given void
    # pointer *box*.
    abstract def unbox(box : Void*) : ForeignValue

    # Returns the corresponding LibFFI type.
    abstract def to_ffi_type : Crystal::FFI::Type

    # Returns the size of this type, in bytes.
    def sizeof : UInt64
      to_ffi_type.@type.value.size
    end

    def from(form : Form) : ForeignValue
      from?(form) || raise Error.new("could not convert #{form} to foreign type #{self}")
    end

    # Instantiates a foreign value of this foreign type from
    # the given *form*.
    #
    # Returns nil if conversion is impossible.
    def from?(form : Form) : ForeignValue?
    end

    # Returns foreign type corresponding to *typename*.
    #
    # Dies if there is no such type.
    def self.parse(this : Block, typename : Word, allow_nothing = true) : ForeignType
      case typename.id
      when "u8"   then U8
      when "u16"  then U16
      when "u32"  then U32
      when "u64"  then U64
      when "i8"   then I8
      when "i16"  then I16
      when "i32"  then I32
      when "i64"  then I64
      when "f32"  then F32
      when "f64"  then F64
      when "cstr" then Cstr
      when "nothing"
        return Nothing if allow_nothing
        typename.die("nothing is not a value type. Did you mean `pointer` (an untyped pointer)?")
      when "pointer" then UntypedPointer
      else
        unless (inline = typename.id.prefixed_by?('~')) || (union_ = typename.id.prefixed_by?('?')) || typename.id.prefixed_by?('&')
          typename.die(
            "could not recognize foreign type. Did you mean `~#{typename}` \
             (inline struct), `&#{typename}` (reference to struct), or \
             `?#{typename}` (union)?")
        end

        typename = Word.new(typename.id.lchop)
        form = this.form_for(typename)
        unless form.as?(StructLayoutForm)
          typename.die("expected struct layout to be value form, not: #{form.class.typedesc}")
        end
        form = form.as(StructLayoutForm)

        if inline
          form.layout.inline
        elsif union_
          form.layout.union
        else
          form.layout.reference
        end
      end
    end

    # Returns whether this type corresponds to the given *value*.
    def matches?(value : ForeignValue) : Bool
      false
    end
  end

  private macro def_decimal_type(name, cr_type, ffi_type, vconv)
    # Type-side and value-side representation of `{{cr_type}}`.
    struct {{name.id}}
      include ForeignValue
      extend ForeignType

      @value : {{cr_type.id}}

      def initialize(decimal)
        @value = decimal.{{vconv}}
      end

      def to_crystal
        @value
      end

      def to_form? : Form?
        # All integer/floating point types are represented by Decimal.
        Decimal.new(to_crystal)
      end

      def self.alloc : Void*
        Pointer({{cr_type}}).malloc(1, 0).as(Void*)
      end

      def self.from?(form : Decimal)
        # Decimal is assumed to implement the usual `to_...`
        # methods, e.g. `to_i32`, which are then called by the
        # corresponding constructor (e.g. `I32.new`).
        new(form)
      end

      def box : Void*
        Pointer({{cr_type.id}}).malloc(1, @value).as(Void*)
      end

      def write_to!(base : Void*)
        base.as({{cr_type.id}}*).value = @value
      end

      def to_s(io)
        io << @value << "_{{name.id.downcase}}"
      end

      def self.to_s(io)
        io << "{{name.id.downcase}}"
      end

      def self.unbox(box : Void*) : ForeignValue
        {{name.id}}.new(box.as({{cr_type.id}}*).value)
      end

      def self.matches?(value : {{name.id}}) : Bool
        true
      end

      def self.to_ffi_type : Crystal::FFI::Type
        Crystal::FFI::Type.{{ffi_type}}
      end

      def_equals_and_hash @value
    end
  end

  def_decimal_type U8, UInt8, uint8, to_u8
  def_decimal_type U16, UInt16, uint16, to_u16
  def_decimal_type U32, UInt32, uint32, to_u32
  def_decimal_type U64, UInt64, uint64, to_u64

  def_decimal_type I8, Int8, sint8, to_i8
  def_decimal_type I16, Int16, sint16, to_i16
  def_decimal_type I32, Int32, sint32, to_i32
  def_decimal_type I64, Int64, sint64, to_i64

  def_decimal_type F32, Float32, float, to_f32
  def_decimal_type F64, Float64, double, to_f64

  # Type-side and value-side representation of pointers.
  struct UntypedPointer
    include ForeignValue
    extend ForeignType

    @address : UInt64

    def initialize(decimal)
      @address = decimal.to_u64
    end

    def self.none
      new(0)
    end

    def none?
      @address.zero?
    end

    def to_form? : Form?
      Decimal.new(@address)
    end

    def self.alloc : Void*
      Pointer(UInt64).malloc(1, 0).as(Void*)
    end

    def self.from?(form : Hole)
      new(form.address)
    end

    def self.from?(form : StructViewForm)
      unless view = form.view.as?(StructReferenceView)
        raise Error.new("cannot implicitly take pointer of struct view that is not a reference struct view")
      end

      new(view.address)
    end

    def self.from?(form : Decimal)
      new(form)
    end

    def box : Void*
      Pointer(UInt64).malloc(1, @address).as(Void*)
    end

    def write_to!(base : Void*)
      base.as(UInt64*).value = @address
    end

    def to_s(io)
      if none?
        io << "(none)"
      else
        io << "("
        @address.to_s(base: 16)
        io << ")"
      end
    end

    def self.to_s(io)
      io << "pointer"
    end

    def self.unbox(box : Void*) : ForeignValue
      if box.null?
        raise Error.new("attempt to unbox none (C nullptr)")
      end

      UntypedPointer.new(box.as(UInt64*).value)
    end

    def self.matches?(value : UntypedPointer) : Bool
      true
    end

    def self.to_ffi_type : Crystal::FFI::Type
      Crystal::FFI::Type.pointer
    end

    def_equals_and_hash @address
  end

  # Type-side and value-side representation of void. All value-side
  # methods raise.
  struct Nothing
    include ForeignValue
    extend ForeignType

    def box : Void*
      raise "BUG: nothing cannot be boxed"
    end

    def write_to!(base : Void*)
      raise "BUG: nothing cannot be written"
    end

    def to_form? : Form?
    end

    def self.alloc : Void*
      raise "BUG: nothing cannot be allocated"
    end

    def to_s(io)
      io << "(void)"
    end

    def self.to_s(io)
      io << "void"
    end

    def self.unbox(box : Void*) : ForeignValue
      Nothing.new
    end

    def self.to_ffi_type : Crystal::FFI::Type
      Crystal::FFI::Type.void
    end
  end

  struct Cstr
    include ForeignValue
    extend ForeignType

    def initialize(@string : String)
    end

    # Returns the corresponding Crystal string.
    def to_crystal : String
      @string
    end

    def to_form? : Form?
      # FIXME: C strings are converted to Crystal strings, which
      # are then wrapped in Quote.
      #
      # Quite dangerous to use this with heap-allocated strings
      # though, because we cannot assume control of them easily --
      # that is, you'd need to know when to free the original
      # string before/after converting it to Crystal string, or
      # else you risk a memory leak.
      Quote.new(to_crystal)
    end

    def to_s(io)
      io << "\"" << to_crystal << "\""
    end

    def self.alloc : Void*
      Pointer(UInt64).malloc(1, 0).as(Void*)
    end

    def self.from?(form : Quote)
      new(form.string)
    end

    def self.to_s(io)
      io << "cstr"
    end

    def box : Void*
      bytes = Pointer(UInt8).malloc(@string.bytesize + 1)
      bytes.copy_from(@string.to_unsafe, @string.bytesize)
      bytes[@string.bytesize + 1] = 0

      Pointer(UInt64).malloc(1, bytes.address).as(Void*)
    end

    def write_to!(base : Void*)
      bytes = Pointer(UInt8).malloc(@string.bytesize + 1)
      bytes.copy_from(@string.to_unsafe, @string.bytesize)
      bytes[@string.bytesize + 1] = 0

      base.as(UInt64*).value = bytes.address
    end

    def self.unbox(box : Void*) : ForeignValue
      handle = Pointer(UInt8).new(box.as(UInt64*).value)
      handle.null? ? UntypedPointer.none : new(String.new(handle))
    end

    def self.matches?(value : Cstr)
      true
    end

    def self.to_ffi_type : Crystal::FFI::Type
      Crystal::FFI::Type.pointer
    end

    def_equals_and_hash @string
  end

  # Holds the description of a struct field: its id (purely for
  # convenience), type (one of `ForeignType`s), and, most
  # importantly, *offset*.
  record StructFieldDesc, id : String, type : ForeignType, offset : UInt64 do
    # Returns the `ForeignValue` found at *base* plus this field's
    # offset, assuming *base* points to the start of the struct this
    # field is a member of.
    #
    # The latter is not enforced; therefore, this method is considered
    # **unsafe**.
    def fetch!(base : Void*) : ForeignValue
      type.unbox Pointer(Void).new(base.address + offset)
    end

    # Writes *value* at *base* plus this field's offset, assuming
    # *base* points to the start of the struct this field is a
    # member of.
    #
    # The latter is not enforced; therefore, this method is considered
    # **unsafe**.
    def put!(base : Void*, value : ForeignValue)
      value.must_be_of type
      value.write_to! Pointer(Void).new(base.address + offset)
    end

    def to_s(io)
      io << "(" << type << " " << id << ")"
    end
  end

  # Allows to describe structs which can then be constructed,
  # retrieved, read, and written to.
  #
  # ```
  # point_s = StructLayout.new("Point")
  # point_s.add("x", F64)
  # point_s.add("y", F64)
  #
  # rect_s = StructLayout.new("Rect")
  # rect_s.add("origin", point_s.reference)
  # rect_s.add("corner", point_s.inline)
  #
  # origin = point_s.reference.make!
  # origin["x"] = F64.new(123)
  # origin["y"] = F64.new(456)
  #
  # corner = point_s.inline.make!
  # corner["x"] = F64.new(234)
  # corner["y"] = F64.new(567)
  #
  # rect = rect_s.reference.make!
  # rect["origin"] = origin
  # rect["corner"] = corner
  #
  # puts rect
  # # &(Rect origin=&(Point x=(f64 123.0) y=(f64 456.0)) corner=(Point x=(f64 234.0) y=(f64 567.0)))
  # ```
  class StructLayout
    # Returns the padded size of this struct. Simply put, this is how
    # much bytes you'd need to allocate for this struct layout.
    getter padded_size : UInt64

    # Returns the alignment of this struct layout.
    getter alignment : UInt64

    getter max_field_size : UInt64

    # Creates an empty struct layout.
    def initialize
      @size = 0u64
      @max_field_size = 0u64
      @alignment = 0u64
      @padded_size = 0u64
      @fields = [] of StructFieldDesc
    end

    # https://github.com/jnr/jnr-ffi/blob/7cecfcf8358b49ab5505cfe6c426f7497e639513/src/main/java/jnr/ffi/StructLayout.java#L99
    private def align(offset, alignment)
      (offset + alignment - 1) & ~(alignment - 1)
    end

    # https://github.com/jnr/jnr-ffi/blob/7cecfcf8358b49ab5505cfe6c426f7497e639513/src/main/java/jnr/ffi/StructLayout.java#L104
    #
    # Aligns and appends a struct field of the given *size*
    # and *align*ment. Returns the field's offset in struct.
    private def add(size, align : UInt64) : UInt64
      offset = align(@size, align)
      @size = Math.max(@size, offset + size)
      @alignment = Math.max(@alignment, align)
      @max_field_size = Math.max(@max_field_size, size)
      @padded_size = align(@size, @alignment)
      offset
    end

    # Extracts size and alignment information from *ffi_type*,
    # and forwards to the next overload of `add`.
    #
    # Returns the field's offset in struct.
    private def add(ffi_type : Crystal::FFI::Type) : UInt64
      add(
        ffi_type.to_unsafe.value.@size.to_u64,
        ffi_type.to_unsafe.value.@alignment.to_u64
      )
    end

    # Appends a field called *id*, of the given *type*, to this
    # struct's list of fields.
    #
    # Similar to struct ids, *id* is irrelevant to FFI and is simply
    # *one of* the ways to access struct fields.
    def add(id, type : ForeignType)
      if type.is_a?(InlineStructType)
        # Use our own data instead of FFI's for inline structs, as the
        # latter seems to be either a) incorrect, b) incompatible with
        # our data, or c) it's me misunderstanding the whole thing.
        offset = add(type.padded_size, type.alignment)
      else
        offset = add(type.to_ffi_type)
      end

      @fields << StructFieldDesc.new(id, type, offset)
    end

    # Returns the amount of fields in this struct layout.
    def field_count
      @fields.size
    end

    # Returns whether this layout contains a field with the given *id*.
    def has_field?(id : String)
      @fields.any? &.id.== id
    end

    # Returns the index of a field with the given *id*, or nil
    # if there is no such field.
    def index?(id : String)
      @fields.index(&.id.== id)
    end

    # Returns the index of a field with the given *id*. Dies if
    # there is no such field.
    def index(id : String)
      index?(id) || raise "BUG: no such field in struct layout: #{id}"
    end

    # Returns field description given the field's *index*inal.
    def desc(index : Int32)
      @fields[index]
    end

    # Returns the description of a field called *id* in this
    # layout. Returns nil if no such field exists.
    def desc?(id : String)
      index?(id).try { |index| @fields.unsafe_fetch(index) }
    end

    # Returns the description of a field called *id* in this
    # layout. Raises if no such field exists.
    def desc(id : String)
      desc?(id) || raise "BUG: no such field: #{id}"
    end

    # Yields field descriptions and their ordinals to the block.
    def each_desc_with_index
      @fields.each_with_index { |field, index| yield field, index }
    end

    # Yields field descriptions and their ordinals to the block.
    # Returns an array of block results.
    def map_desc_with_index
      @fields.map_with_index { |field, index| yield field, index }
    end

    # Returns a struct reference type corresponding to this struct
    # layout. You then can use it as such in your struct field /
    # argument types.
    #
    # Note: this method costs nothing. Feel free to spam `.reference`
    # instead of saving it in a variable and using that variable.
    def reference
      StructReferenceType.new(self)
    end

    # Returns an inline struct type corresponding to this struct
    # layout. You then can use it as such in your struct field /
    # argument types.
    #
    # Note: this method costs nothing. Feel free to spam `.inline`
    # instead of saving it in a variable and using that variable.
    def inline
      InlineStructType.new(self)
    end

    def union
      UnionType.new(self)
    end

    def to_s(io)
      executed = exec_recursive(:to_s) do
        io << "⟪"
        @fields.join(io, ", ") do |field, io|
          io << field.id << "=" << field.type
        end
        io << "⟫"
      end
      io << "[reflection]" unless executed
    end

    # Returns whether this and *other* layouts are the same layout.
    # Uses reference equality (`same?`) rather than deep equality.
    def ==(other : StructLayout)
      # We don't compare layouts often, so we use simple pointer
      # equality rather than deep equality. This lets us avoid
      # the problem of writing complex, recursive reference-aware
      # comparison code like in Block.
      same?(other)
    end
  end

  # Base class of the *type* side of structs.
  abstract struct StructType
    include ForeignType

    def initialize(@layout : StructLayout)
    end

    # See `StructLayout`.
    delegate :padded_size, :alignment, to: @layout

    # Returns the struct view corresponding to this struct type,
    # wrapped around the given *handle*.
    abstract def view_for(handle : Void*) : StructView

    def from?(form : StructViewForm)
      form.view
    end

    delegate :references?, to: @layout

    # Constructs a struct view for this struct type.
    #
    # This method is **unsafe**: the resulting struct view's content
    # is unmoderated. You'll need to fill all fields with values
    # before the struct view could be considered well-defined.
    def make! : StructView
      view_for Pointer(Void).malloc(@layout.padded_size)
    end

    def to_s(io)
      io << @layout
    end
  end

  # *Type-side* representation of a struct reference, aka struct
  # pointer, aka heap-allocated struct (like Crystal `class`).
  struct StructReferenceType < StructType
    def alloc : Void*
      Pointer(UInt64).malloc(1, 0).as(Void*)
    end

    def view_for(handle : Void*) : StructView
      StructReferenceView.new(@layout, handle)
    end

    def unbox(box : Void*) : ForeignValue
      handle = Pointer(Void).new(box.as(UInt64*).value)
      handle.null? ? UntypedPointer.none : view_for(handle)
    end

    def to_ffi_type : Crystal::FFI::Type
      Crystal::FFI::Type.pointer
    end

    def matches?(view : StructReferenceView) : Bool
      @layout.same?(view.@layout)
    end

    def matches?(pointer : UntypedPointer)
      pointer.none?
    end

    def to_s(io)
      io << "&"
      super
    end
  end

  # *Type-side* representation of an inline struct, e.g. one returned
  # from a function or passed as an argument, aka stack-allocated
  # structs (like Crystal `struct`).
  struct InlineStructType < StructType
    def sizeof : UInt64
      padded_size
    end

    def alloc : Void*
      Pointer(Void).malloc(self.sizeof)
    end

    def view_for(handle : Void*) : StructView
      InlineStructView.new(@layout, handle)
    end

    def unbox(box : Void*) : ForeignValue
      box.null? ? UntypedPointer.none : view_for(box)
    end

    def to_ffi_type : Crystal::FFI::Type
      Crystal::FFI::Type.struct(@layout.map_desc_with_index &.type.to_ffi_type)
    end

    def matches?(view : InlineStructView) : Bool
      @layout.same?(view.@layout)
    end

    def to_s(io)
      io << "~"
      super
    end
  end

  struct UnionType < StructType
    def sizeof : UInt64
      @layout.max_field_size
    end

    def alloc : Void*
      Pointer(Void).malloc(self.sizeof)
    end

    def view_for(handle : Void*) : StructView
      UnionView.new(@layout, handle)
    end

    def unbox(box : Void*) : ForeignValue
      box.null? ? UntypedPointer.none : view_for(box)
    end

    def to_ffi_type : Crystal::FFI::Type
      Crystal::FFI::Type.pointer
    end

    def matches?(view : UnionView) : Bool
      @layout.same?(view.@layout)
    end

    def to_s(io)
      io << "⋃"
      super
    end
  end

  # Base class of the *value* side of structs.
  #
  # Implements `Indexable` and `Indexable::Mutable` over the fields in
  # the struct, allowing you to iterate, read, and change them (with
  # some casting from and to `ForeignValue` though.)
  abstract struct StructView
    include ForeignValue
    include Indexable(ForeignValue)
    include Indexable::Mutable(ForeignValue)

    def initialize(@layout : StructLayout, @handle : Void*)
    end

    delegate :has_field?, to: @layout
    delegate :address, to: @handle

    def size
      @layout.field_count
    end

    def unsafe_put(index : Int, value : ForeignValue)
      @layout.desc(index).put!(@handle, value)
    end

    def unsafe_fetch(index : Int)
      @layout.desc(index).fetch!(@handle)
    end

    # Assigns *value* to a field named *id*.
    def []=(id : String, value : ForeignValue)
      unsafe_put(@layout.index(id), value)
    end

    # Returns the value of a field named *id*. Dies if there is
    # no such field.
    def [](id : String)
      unsafe_fetch(@layout.index(id))
    end

    # Returns the value of a field named *id*, or nil if there
    # is no such field.
    def []?(id : String)
      if index = @layout.index?(id)
        unsafe_fetch(index)
      end
    end

    def to_form? : Form?
      StructViewForm.new(self)
    end

    def to_s(io)
      @layout.each_desc_with_index do |desc, index|
        io << desc.id << "=" << unsafe_fetch(index)
        io << ", " unless index == @layout.field_count - 1
      end
    end

    def ==(other : StructView)
      equals?(other) { |a, b| a == b }
    end

    def_hash @handle
  end

  # *Value-side* representation of a struct reference, aka struct
  # pointer, aka heap-allocated struct. Allows to read and write
  # fields (see `StructView`). Similar to the `->` operator in C.
  struct StructReferenceView < StructView
    def box : Void*
      Pointer(UInt64).malloc(1, @handle.address).as(Void*)
    end

    def write_to!(base : Void*)
      base.as(UInt64*).value = @handle.address
    end

    # Similar to `exec_recursive`, but instead of using object_id
    # (which is not available nor useful here), uses the handle
    # pointer (which is the same thing as object_id but "viewed
    # from the side").
    private def exec_recursive_by_handle(method)
      hash = Reference::ExecRecursive.hash
      key = {@handle.address, method}
      if hash[key]?
        false
      else
        hash[key] = true
        yield
        hash.delete(key)
        true
      end
    end

    def ==(other : StructReferenceView)
      return true if @handle == other.@handle
      return false unless size == other.size
      result = false
      executed = exec_recursive_by_handle(:==) do
        result = super
      end
      executed && result
    end

    def to_s(io)
      executed = exec_recursive_by_handle(:to_s) do
        io << "&⟨"
        super
        io << "⟩"
      end
      unless executed
        io << "[reflection]"
      end
    end
  end

  # *Value-side* representation of an inline struct, aka
  # stack-allocated struct. Allows to read and write fields (see
  # `StructView`). Similar to the `.` operator in C.
  struct InlineStructView < StructView
    def box : Void*
      @handle
    end

    def write_to!(base : Void*)
      # Copy the contents of this struct to the destination pointer.
      # We use `move_to` because we don't know *anything* about
      # *pointer*, and `move_to` is safer in such cases (I guess).
      @handle.move_to(base, @layout.padded_size)
    end

    def to_s(io)
      io << "~⟨"
      super
      io << "⟩"
    end
  end

  struct UnionView < StructView
    def size
      @layout.field_count
    end

    def unsafe_put(index : Int, value : ForeignValue)
      desc = @layout.desc(index)
      value.must_be_of(desc.type)
      value.write_to!(@handle)
    end

    def unsafe_fetch(index : Int)
      desc = @layout.desc(index)
      desc.type.unbox(@handle)
    end

    def box : Void*
      @handle
    end

    def write_to!(base : Void*)
      @handle.move_to(base, @layout.max_field_size)
    end

    def to_s(io)
      io << "(⋃ " << @layout << ")"
    end
  end

  abstract struct Function
    abstract def id : String
    abstract def call(block : Block) : Form?
  end

  # An interface to describe and call C functions at runtime.
  struct FixedArityFunction < Function
    # Returns the identifier of this function.
    getter id : String

    def initialize(@id, @handle : Void*, @argtypes : Array(ForeignType), @return_type : ForeignType)
      @cif = Crystal::FFI::CallInterface.new(@return_type.to_ffi_type, @argtypes.map(&.to_ffi_type))
    end

    # Calls this function with the given arguments. Returns the
    # resulting value (or `Nothing` in case of `void`).
    def call(args = [] of ForeignValue) : ForeignValue
      raise "BUG: argument count mismatch" unless args.size == @argtypes.size

      # Make sure arguments are of the correct type.
      @argtypes.zip(args) { |argtype, arg| arg.must_be_of(argtype) }

      # Allocate argument array with boxed arguments, and a hole for
      # the return value.
      cargs = Pointer(Void*).malloc(args.size) { |index| args[index].box }
      creturn = Pointer(Void).malloc(@return_type.sizeof)

      @cif.call(@handle, cargs, creturn)

      # Interpret the return hole as a pointer to whatever type the
      # user declared this function returns. Unbox to obtain the
      # actual value.
      @return_type.unbox(creturn)
    end

    def call(block : Block) : Form?
      args = [] of ForeignValue
      @argtypes.reverse_each do |argtype|
        args.unshift argtype.from(block.drop)
      end
      call(args).to_form?
    end
  end

  struct VariadicFunction < Function
    getter id : String

    def initialize(@id, @handle : Void*, @fixed_arg_types : Array(ForeignType), @va_allowed : Array(ForeignType), @return_type : ForeignType)
    end

    def call(block : Block) : Form?
      # Drop varargs block.
      va_list = block.drop.a(Block)

      # Drop fixed arguments.
      fixed_args = [] of ForeignValue
      @fixed_arg_types.reverse_each do |argtype|
        fixed_args.unshift argtype.from(block.drop)
      end

      # Make sure fixed arguments are of the correct type.
      @fixed_arg_types.zip(fixed_args) { |argtype, arg| arg.must_be_of(argtype) }

      # Go through the varargs block, make sure each form there
      # is of the allowed type & make a foreign value out of it.
      va_types = [] of ForeignType
      va_args = [] of ForeignValue

      va_list.each do |form|
        type_candidates = @va_allowed
          .map { |rtype| {rtype, rtype.from?(form)} }
          .select { |_, rtype_form| rtype_form }

        unless type_candidates.size == 1
          form.die(
            "unable to convert to foreign value: too many or no type \
             candidates for form. Make sure you've specified the \
             corresponding foreign type in the variadic function's set \
             of allowed types, and no conflicts between types exist \
             (e.g. i32 and i64; this is currently unsupported)")
        end

        va_types << type_candidates.first.[0]
        va_args << type_candidates.first.[1].not_nil!
      end

      cif = Crystal::FFI::CallInterface.variadic(@return_type.to_ffi_type, (@fixed_arg_types + va_types).map &.to_ffi_type, @fixed_arg_types.size)

      cargs = Pointer(Void*).malloc(fixed_args.size + va_args.size)
      fixed_args.each_with_index do |fixed_arg, index|
        (cargs + index).as(Void**).value = fixed_arg.box.as(Void*)
      end
      va_args.each_with_index do |va_arg, index|
        (cargs + index + fixed_args.size).as(Void**).value = va_arg.box.as(Void*)
      end

      creturn = Pointer(Void).malloc(@return_type.sizeof)

      cif.call(@handle, cargs, creturn)

      @return_type.unbox(creturn).to_form?
    end
  end
end
