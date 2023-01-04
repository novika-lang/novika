require "compiler/crystal/ffi"

module Novika::FFI
  # Base type for Novika FFI values (both heap & stack allocated).
  module ForeignValue
    # Wraps this value in a void pointer.
    abstract def box : Void*

    # Writes this value starting at the given *base* pointer.
    # Returns the *base* pointer.
    abstract def write_to!(base : Void*) : Void*

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

    # Instantiates a foreign value of this foreign type from
    # the given *form*.
    #
    # Dies if conversion is impossible.
    def from(form : Form) : ForeignValue
      from?(form) || raise Error.new("could not convert #{form} to foreign type #{self}")
    end

    # Instantiates a foreign value of this foreign type from
    # the given *form*.
    #
    # Returns nil if conversion is impossible.
    def from?(form : Form) : ForeignValue?
    end

    # Returns whether this type corresponds to the given *value*.
    def matches?(value : ForeignValue) : Bool
      false
    end
  end

  # An object used to translate `Word`s (representing a foreign type)
  # into actual `ForeignType`s.
  abstract struct TypeParser
    # If included, the parser would die upon encountering `nothing`.
    module ForbidsNothing
      def on_primitive(type : Nothing.class)
        @typename.die("nothing is not a value type. Did you mean `pointer` (an untyped pointer)?")
      end
    end

    # Initializes a parser object from *this*, a block that will be
    # asked for word definitions in case they are needed, and
    # *typename*, which is the word-to-be-parsed itself.
    def initialize(@this : Block, @typename : Word)
    end

    # Primitive *type* middleware.
    def on_primitive(type : ForeignType) : ForeignType
      type
    end

    # Union-annotated struct layout middleware.
    def on_union(form : StructLayoutForm) : ForeignType
      form.layout.union
    end

    # Inline struct-annotated struct layout middleware.
    def on_inline_struct(form : StructLayoutForm) : ForeignType
      form.layout.inline
    end

    # Struct reference-annotated struct layout middleware.
    def on_struct_reference(form : StructLayoutForm) : ForeignType
      form.layout.reference
    end

    # Performs the parsing. Returns the resulting type.
    def parse : ForeignType
      case @typename.id
      when "u8"      then return on_primitive(U8)
      when "u16"     then return on_primitive(U16)
      when "u32"     then return on_primitive(U32)
      when "u64"     then return on_primitive(U64)
      when "i8"      then return on_primitive(I8)
      when "i16"     then return on_primitive(I16)
      when "i32"     then return on_primitive(I32)
      when "i64"     then return on_primitive(I64)
      when "f32"     then return on_primitive(F32)
      when "f64"     then return on_primitive(F64)
      when "cstr"    then return on_primitive(Cstr)
      when "char"    then return on_primitive(Cchar)
      when "pointer" then return on_primitive(UntypedPointer)
      when "nothing" then return on_primitive(Nothing)
      when .prefixed_by?('?')
        handler = ->on_union(StructLayoutForm)
      when .prefixed_by?('~')
        handler = ->on_inline_struct(StructLayoutForm)
      when .prefixed_by?('&')
        handler = ->on_struct_reference(StructLayoutForm)
      else
        @typename.die(
          "could not recognize foreign type. Did you mean `~#{@typename}` \
           (inline struct), `&#{@typename}` (reference to struct), or \
           `?#{@typename}` (union)?")
      end

      raw = Word.new(@typename.id.lchop)
      form = @this.form_for(raw)
      unless form.is_a?(StructLayoutForm)
        @typename.die("expected struct layout to be value form, not: #{form.class.typedesc}")
      end

      handler.call(form)
    end
  end

  # Allows all parse-able types, from ints to `nothing` to
  # structs and unions.
  struct DefaultTypeParser < TypeParser
  end

  # Same as `DefaultTypeParser`, but forbids nothing.
  #
  # ```
  # # this : Block
  #
  # parser = ValueTypeParser.new(this, Word.new("i32"))
  # parser.parse # => I32
  #
  # # ...
  #
  # parser = ValueTypeParser.new(this, Word.new("nothing"))
  # parser.parse # Dies: nothing is not a value type.
  # ```
  struct ValueTypeParser < TypeParser
    include TypeParser::ForbidsNothing
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

      def write_to!(base : Void*) : Void*
        base.as({{cr_type.id}}*).value = @value
        base
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
        raise Error.new(
          "cannot implicitly take pointer of struct view that is \
           not a reference struct view")
      end

      new(view.address)
    end

    def self.from?(form : Decimal)
      new(form)
    end

    def box : Void*
      Pointer(UInt64).malloc(1, @address).as(Void*)
    end

    def write_to!(base : Void*) : Void*
      base.as(UInt64*).value = @address
      base
    end

    def to_s(io)
      if none?
        io << "(none)"
      else
        io << "("
        @address.to_s(io, base: 16)
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

    def write_to!(base : Void*) : Void*
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

  # Type-side and value-side representation of C char (a u8).
  # In Novika, char is represented by a single-character quote.
  struct Cchar
    include ForeignValue
    extend ForeignType

    def initialize(@char : UInt8)
    end

    # Returns the corresponding Crystal character.
    def to_crystal
      @char.chr
    end

    def to_form? : Form?
      Quote.new(to_crystal)
    end

    def self.from?(form : Quote)
      form.first_byte?.try { |byte| new(byte) }
    end

    def self.from?(form : Decimal)
      new(form.to_u8)
    end

    def to_s(io)
      io << "'" << to_crystal << "'"
    end

    def self.alloc : Void*
      Pointer(UInt8).malloc(1, 0).as(Void*)
    end

    def self.to_s(io)
      io << "char"
    end

    def box : Void*
      Pointer(UInt8).malloc(1, @char).as(Void*)
    end

    def write_to!(base : Void*) : Void*
      base.as(UInt8*).value = @char
      base
    end

    def self.unbox(box : Void*) : ForeignValue
      new(box.as(UInt8*).value)
    end

    def self.matches?(value : Cchar)
      true
    end

    def self.to_ffi_type : Crystal::FFI::Type
      Crystal::FFI::Type.uint8
    end
  end

  # Type-side and value-side representation of C string (a u8 pointer).
  # In Novika, C string is represented by a quote.
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
      write_to! Pointer(UInt64).malloc(1).as(Void*)
    end

    def write_to!(base : Void*) : Void*
      bytes = Pointer(UInt8).malloc(@string.bytesize + 1)
      bytes.copy_from(@string.to_unsafe, @string.bytesize)
      bytes[@string.bytesize + 1] = 0

      base.as(UInt64*).value = bytes.address
      base
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
      value.must_be_of(type)
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
  # ```
  class StructLayout
    # Returns the padded size of this struct. Simply put, this is how
    # much bytes you'd need to allocate for this struct layout.
    getter padded_size : UInt64

    # Returns the alignment of this struct layout.
    getter alignment : UInt64

    # Returns the maximum field size in this struct.
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

    # Returns whether this layout contains a field with the
    # given *id*entifier.
    def has_field?(id : String)
      @fields.any? &.id.== id
    end

    # Returns the index of a field with the given *id*entifier,
    # or nil if there is no such field.
    def index?(id : String)
      @fields.index(&.id.== id)
    end

    # Returns the index of a field with the given *id*entifier.
    # Dies if there is no such field.
    def index(id : String)
      index?(id) || raise "BUG: no such field in struct layout: #{id}"
    end

    # Retrieves field description given the field's *index*.
    def desc(index : Int32)
      @fields[index]
    end

    # Retrieves field description given the field's *id*entifier.
    # Returns nil if no such field exists.
    def desc?(id : String)
      index?(id).try { |index| @fields.unsafe_fetch(index) }
    end

    # Retrieves field description given the field's *id*entifier.
    # Raises if no such field exists.
    def desc(id : String)
      desc?(id) || raise "BUG: no such field: #{id}"
    end

    # Yields field descriptions and their indices to the block.
    def each_desc_with_index
      @fields.each_with_index { |field, index| yield field, index }
    end

    # Yields field descriptions and their indices to the block.
    # Returns an array of block results.
    def map_desc_with_index
      @fields.map_with_index { |field, index| yield field, index }
    end

    # Returns a struct reference type layed out according to this struct
    # layout. You can then use it in your struct field / argument types.
    #
    # Note: this method costs nothing. Feel free to spam `.reference`
    # instead of saving it in a variable and using that variable.
    def reference
      StructReferenceType.new(self)
    end

    # Returns an inline struct type layed out according to this struct
    # layout. You can then use it in your struct field / argument types.
    #
    # Note: this method costs nothing. Feel free to spam `.inline`
    # instead of saving it in a variable and using that variable.
    def inline
      InlineStructType.new(self)
    end

    # Returns a union type layed out according to this struct layout.
    # You can then use it in your struct field / argument types.
    #
    # Note: this method costs nothing. Feel free to spam `.union`
    # instead of saving it in a variable and using that variable.
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

    # Returns whether this and *other* layouts are the same
    # layout. Uses reference equality (like `same?`) rather
    # than deep equality.
    def_equals_and_hash object_id
  end

  # Base type of the *type* side of structs.
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

    # See `StructLayout`.
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
      @layout.same?(view.layout)
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
      @layout.same?(view.layout)
    end

    def to_s(io)
      io << "~"
      super
    end
  end

  # *Type-side* representation of a union.
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
      @layout.same?(view.layout)
    end

    def to_s(io)
      io << "⋃"
      super
    end
  end

  # Base type of the *value* side of structs.
  #
  # Implements `Indexable` and `Indexable::Mutable` over the fields in
  # the struct, allowing you to iterate, read, and change them (with
  # some casting from and to `ForeignValue` though.)
  abstract struct StructView
    include ForeignValue
    include Indexable(ForeignValue)
    include Indexable::Mutable(ForeignValue)

    # Returns this view's struct layout.
    getter layout : StructLayout

    def initialize(@layout, @handle : Void*)
    end

    # See `StructLayout`.
    delegate :has_field?, to: @layout

    # Returns the pointer address of the struct this view refers to.
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

    # Assigns *value* to a field with the given *id*entifier.
    def []=(id : String, value : ForeignValue)
      unsafe_put(@layout.index(id), value)
    end

    # Returns the value of a field with the given *id*entifier.
    # Dies if there is no such field.
    def [](id : String)
      unsafe_fetch(@layout.index(id))
    end

    # Returns the value of a field with the given *id*entifier,
    # or nil if there is no such field.
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

    def write_to!(base : Void*) : Void*
      base.as(UInt64*).value = @handle.address

      base
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

    def write_to!(base : Void*) : Void*
      @handle.move_to(base, @layout.padded_size)

      base
    end

    def to_s(io)
      io << "~⟨"
      super
      io << "⟩"
    end
  end

  # *Value-side* representation of a union.
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

    def write_to!(base : Void*) : Void*
      @handle.move_to(base, @layout.max_field_size)

      base
    end

    def to_s(io)
      io << "(⋃ " << @layout << ")"
    end
  end

  # Base type for C function call interfaces.
  abstract struct Function
    # Returns the identifier of this function.
    abstract def id : String

    # Drops arguments from *block* and calls this function.
    # Returns the resulting form, or nil in case this function
    # returns `Nothing` (C `void`).
    abstract def call(block : Block) : Form?
  end

  # Calls a fixed-arity C function.
  struct FixedArityFunction < Function
    getter id : String

    def initialize(@id, @handle : Void*, @argtypes : Array(ForeignType), @return_type : ForeignType)
      @cif = Crystal::FFI::CallInterface.new(@return_type.to_ffi_type, @argtypes.map(&.to_ffi_type))
    end

    private def call(args : Array(ForeignValue)) : ForeignValue
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
        arg = argtype.from(block.drop)
        arg.must_be_of(argtype)
        args.unshift(arg)
      end
      call(args).to_form?
    end
  end

  # Calls a variadic C function.
  struct VariadicFunction < Function
    getter id : String

    def initialize(
      @id,
      @handle : Void*,
      @fixed_arg_types : Array(ForeignType),
      @var_arg_allowed : Array(ForeignType),
      @return_type : ForeignType
    )
    end

    def call(block : Block) : Form?
      var_args_block = block.drop.a(Block)

      ffi_args = [] of ForeignValue
      ffi_types = [] of Crystal::FFI::Type

      # Drop fixed arguments first into the arguments array.
      @fixed_arg_types.reverse_each do |argtype|
        ffi_types.unshift(argtype.to_ffi_type)
        arg = argtype.from(block.drop)
        arg.must_be_of(argtype)
        ffi_args.unshift(arg)
      end

      # Go through the varargs block, make sure each form there
      # is of an allowed type & make a foreign value out of it.
      var_args_block.each do |form|
        candidates = @var_arg_allowed
          .map { |type| {type, type.from?(form)} }
          .select { |_, value| value }

        unless candidates.size == 1
          form.die(
            "unable to convert to foreign value: too many or no type \
             candidates for form. Make sure you've specified the \
             corresponding foreign type in the variadic function's list \
             of allowed types, and no conflicts between types exist \
             (e.g. both i32 and i64; this is currently unsupported)")
        end

        candidate = candidates[0]
        candidate_type, candidate_value = candidate
        candidate_value = candidate_value.not_nil!

        ffi_types << candidate_type.to_ffi_type
        ffi_args << candidate_value
      end

      # Variadic functions need a call interface for each call.
      cif = Crystal::FFI::CallInterface.variadic(
        return_type: @return_type.to_ffi_type,
        arg_types: ffi_types,
        fixed_args: @fixed_arg_types.size
      )

      cargs = Pointer(Void*).malloc(ffi_args.size) { |index| ffi_args[index].box }
      creturn = Pointer(Void).malloc(@return_type.sizeof)

      cif.call(@handle, cargs, creturn)

      @return_type.unbox(creturn).to_form?
    end
  end
end
