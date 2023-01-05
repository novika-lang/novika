module Novika::Features::Impl
  class FFI
    include Feature

    def self.id : String
      "ffi"
    end

    def self.purpose : String
      "exposes words for working with foreign functions, structs, and unions"
    end

    def self.on_by_default? : Bool
      true
    end

    def inject(into target : Block)
      target.at("ffi:library?", <<-END
      ( F -- true/false ): leaves whether Form is a foreign
       library form.

      ```
      'foo' ffi:getLibrary ffi:library? leaves: true
      ```
      END
      ) { |_, stack| Boolean[stack.drop.is_a?(Library)].onto(stack) }

      target.at("ffi:layout?", <<-END
      ( F -- true/false ): leaves whether Form is a foreign
       layout form.

      ```
      [ x i32 y i32 ] ffi:createLayout $: point

      point ffi:layout? leaves: true
      ```
      END
      ) { |_, stack| Boolean[stack.drop.is_a?(StructLayoutForm)].onto(stack) }

      target.at("ffi:struct&?", <<-END
      ( F -- true/false ): leaves whether Form is a struct
       reference view form.

      ```
      [ x i32 y i32 ] ffi:createLayout $: point

      point ffi:allocateStruct& $: point&
      point& ffi:struct&? leaves: true
      ```
      END
      ) { |_, stack| Boolean[stack.drop.as?(StructViewForm).try &.reference?].onto(stack) }

      target.at("ffi:struct~?", <<-END
      ( F -- true/false ): leaves whether Form is an inline
       struct view form.

      ```
      [ x i32 y i32 ] ffi:createLayout $: point

      point ffi:allocateStruct~ $: point~
      point~ ffi:struct~? leaves: true
      ```
      END
      ) { |_, stack| Boolean[stack.drop.as?(StructViewForm).try &.inline?].onto(stack) }

      target.at("ffi:union?", <<-END
      ( F -- true/false ): leaves whether Form is a union
       view form.

      ```
      [ chr char ord u8 ] ffi:createLayout $: quux

      quux ffi:allocateUnion $: quuxU
      quuxU ffi:union? leaves: true
      ```
      END
      ) { |_, stack| Boolean[stack.drop.as?(StructViewForm).try &.union?].onto(stack) }

      target.at("ffi:hole?", <<-END
      ( F -- true/false ): leaves whether Form is a hole.

      ```
      #i32 ffi:hole $: intHole

      intHole ffi:hole? leaves: true
      ```
      END
      ) { |_, stack| Boolean[stack.drop.is_a?(Hole)].onto(stack) }

      target.at("ffi:getLibrary?", <<-END
      ( I -- Lf true / false ): leaves Library form followed by true
       if dynamic library with the given Id exists and was loaded &
       retrieved successfully; otherwise, leaves false.

      Opening Library form allows one to expose functions from
      it. See FFI documentation on GitHub Wiki for more details
      and examples

      ```
      'SDL2' ffi:getLibrary? leaves: [ "[foreign library]" true ]
      'random-nonexisting-library' ffi:getLibrary? leaves: false
      ```
      END
      ) do |engine, stack|
        id = stack.drop.a(Quote)
        if library = engine.bundle.load_library?(id.string)
          library.onto(stack)
        end
        Boolean[!!library].onto(stack)
      end

      target.at("ffi:getLibrary", <<-END
      ( I -- Lf ): leaves Library form if dynamic library with the
       given Id exists and was loaded & retrieved successfully;
       otherwise, dies.

      Opening Library form allows one to expose functions from
      it. See FFI documentation on GitHub Wiki for more details
      and examples.

      ```
      'SDL2' ffi:getLibrary ffi:library? leaves: true
      'random-nonexisting-library' ffi:getLibrary "Dies: no such library"
      ```
      END
      ) do |engine, stack|
        id = stack.drop.a(Quote)
        unless library = engine.bundle.load_library?(id.string)
          id.die("no such library")
        end
        library.onto(stack)
      end

      target.at("ffi:createLayout", <<-END
      ( Lb -- Slf ): parses Layout block and leaves the resulting
       Struct layout form.

      Struct layouts are a generalization over structs (heap-
      allocated and stack-allocated), and unions. They literally
      describe how structs (unions) are layed out in memory.

      Layout block consists of *name words followed by type words*.
      See the example below. A reference to another struct layout
      can be made in Layout block using the prefixes `&` (heap-
      allocated struct, i.e., pointer to struct), `~` (inline or
      stack-allocated struct), and `?` (stack-allocated union).

      Inline struct cycles are forbidden. Union cycles are forbidden.
      Either could be hidden behind a reference/pointer.

      Layout block is parsed lazily (on first use, e.g., by `toQuote`,
      `allocateStruct` variants, etc.) Therefore, you can define self-
      referential structs, mutually referential structs, and reference
      layouts that are defined later.

      See FFI documentation on GitHub Wiki for a list of available
      types and the corresponding C types.

      ```
      [ x f32
        y f32
      ] ffi:createLayout $: point

      [ datum ~point    "<- inline struct"
        next &pointNode "<- struct reference"
      ] ffi:createLayout $: pointNode

      [ asPoint &point
        asPointNode ~pointNode
      ] ffi:createLayout $: pointNodeUnion

      [ type u8
        value ?pointNodeUnion "<- stack-allocated union"
      ] ffi:createLayout $: pointNodeOrPoint
      ```
      END
      ) do |engine, stack|
        decl = stack.drop.a(Block)
        this = engine.block

        names = [] of Word
        types = [] of Word
        cur, nxt = names, types

        decl.each do |form|
          unless form.is_a?(Word)
            form.die(
              "only words (for field name and for field type) are allowed \
               in struct layout declaration")
          end

          cur << form
          cur, nxt = nxt, cur
        end

        unless names.size == types.size
          decl.die("malformed struct layout: missing field name or type")
        end

        if names.empty? # && types.empty?
          decl.die("struct layout must have at least one field")
        end

        StructLayoutForm.new(this, names, types).onto(stack)
      end

      {% for method, desc in {
                               inline:    {"~", :InlineStruct, "Isv", "an Inline struct"},
                               reference: {"&", :StructReference, "Srv", "a Struct reference"},
                             } %}

        {% sign, cls, ann, qual = desc %}

        target.at("ffi:allocateStruct{{sign.id}}", <<-END
        ( Slf -- {{ann.id}} ): allocates {{qual.id}} view for the
         given Struct layout form.

        This word is **unsafe**: the resulting {{qual.id}} view is
        in an undefined state (may contain junk) before you (or the
        C code you pass it to) fills it with good values. Showing
        the struct view left by this word to clients may expose your
        program to a whole class of security vulnerabilities.

        ```
        [ x i32 y i32 ] ffi:createLayout $: point

        point ffi:allocateStruct{{sign.id}} $: point{{sign.id}}
        point{{sign.id}} #x 123 entry:submit
        point{{sign.id}} #y 456 entry:submit
        point{{sign.id}} toQuote leaves: '{{sign.id}}⟨x=123_i32, y=456_i32⟩'
        ```
        END
        ) do |_, stack|
          form = stack.drop.a(StructLayoutForm)
          view = form.layout.{{method.id}}.make!
          StructViewForm.new(view).onto(stack)
        end

        target.at("ffi:buildStruct{{sign.id}}", <<-END
        ( Eb Slf -- {{ann.id}} ): allocates and fills {{qual.id}}
         view with entries by asking Entry block for them.

        If Entry block is missing a field that Struct layout form
        declares, and that field is of `pointer` or struct reference
        (`&`) type, `none` (C nullptr) is used as the value. Dies if
        Entry block is missing a field of any other type.

        ```
        [ x i32 y i32 ] ffi:createLayout $: point

        100 $: x
        200 $: y

        "Note: `this` has entries called `x` and `y`. `point` has
         fields called `x` and `y`. A match!"
        this point ffi:buildStruct{{sign.id}} $: point{{sign.id}}

        point{{sign.id}} toQuote leaves: '{{sign.id}}⟨x=100_i32, y=200_i32⟩'
        ```
        END
        ) do |_, stack|
          layout_form = stack.drop.a(StructLayoutForm)
          block = stack.drop.a(Block)
          layout = layout_form.layout
          view = layout.{{method.id}}.make!
          layout.each_desc_with_index do |desc|
            entry = block.entry_for? Word.new(desc.id)
            if entry
              view[desc.id] = desc.type.from(entry.form)
            elsif desc.type.is_a?(Novika::FFI::UntypedPointer.class) || desc.type.is_a?(Novika::FFI::StructReferenceType)
              view[desc.id] = Novika::FFI::UntypedPointer.none
            else
              block.die(
                "block is missing field '#{desc.id}'. Note that none (C nullptr) \
                 as default value is only supported for untyped pointers (`pointer`) \
                 and struct references (`&name`)")
            end
          end
          StructViewForm.new(view).onto(stack)
        end

        target.at("ffi:asStruct{{sign.id}}", <<-END
        ( Pd Slf -- {{ann.id}} ): wraps Pointer decimal in {{qual.id}}
         view according to the given Struct layout form.

        This word is **unsafe**: it does not check whether Pointer
        decimal points at something that is layed out according to
        Struct layout form. Passing 0 for Pointer decimal will lead
        to segfault. Passing a pointer that points outside of your
        program's memory will lead to segfault. Passing a pointer
        that *is* in the bounds of your program's memory, but one
        not pointing at a struct in accordance to Struct layout form,
        will lead to undefined behavior (most likely junk values
        in {{qual.id}} view).

        ```
        [ x i32 y i32 ] ffi:createLayout $: point

        100 $: x
        200 $: y
        this point ffi:buildStruct{{sign.id}} $: point{{sign.id}}

        point{{sign.id}} ffi:addressof $: addr

        addr point ffi:asStruct{{sign.id}} $: addrPoint{{sign.id}}
        addrPoint{{sign.id}}.x leaves: x
        addrPoint{{sign.id}}.y leaves: y
        addrPoint{{sign.id}} toQuote leaves: '{{sign.id}}⟨x=100_i32, y=200_i32⟩'
        ```
        END
        ) do |_, stack|
          layout_form = stack.drop.a(StructLayoutForm)
          pointer = stack.drop.a(Decimal)
          view = Novika::FFI::{{cls.id}}View.new(layout_form.layout, Pointer(Void).new(pointer.to_u64))
          StructViewForm.new(view).onto(stack)
        end
      {% end %}

      target.at("ffi:allocateUnion", <<-END
      ( Slf -- Uv ): allocates Union view for the given Struct
       layout form.

      This word is **unsafe**: the resulting Union view is in
      an undefined state (may contain junk) before you (or the
      C code you pass it to) fills it with good values. Showing
      the union left by this word to clients may expose your
      program to a whole class of security vulnerabilities.

      ```
      [ chr char
        ord u8
      ] ffi:createLayout $: quux

      quux ffi:allocateUnion $: quuxUnion
      quuxUnion #chr 'A' entry:submit
      quuxUnion.ord leaves: 65

      "Union toQuote avoids printing values, because that could
       cause a segfault/overflow in some cases, and would mostly
       output junk anyway."
      quuxUnion toQuote leaves: '(⋃ ⟪chr=char, ord=u8⟫)'
      ```
      END
      ) do |_, stack|
        form = stack.drop.a(StructLayoutForm)
        view = form.layout.union.make!
        StructViewForm.new(view).onto(stack)
      end

      target.at("ffi:buildUnion", <<-END
      ( Eb Slf -- Uv ): allocates and fills Union view with an
       entry by asking Entry block for any *one* entry in Struct
       layout form, in the order they are specified in Sruct
       layout form.

      Entry block must have at least one of the Struct layout
      form's fields defined. Otherwise, this word dies.

      ```
      [ chr char
        ord u8
      ] ffi:createLayout $: quux

      [ 'A' $: chr
        this quux ffi:buildUnion
      ] val $: unionByChr

      [ 66 $: ord
        this quux ffi:buildUnion
      ] val $: unionByOrd

      [ 'A' $: chr
        123 $: ord
        this quux ffi:buildUnion
      ] val $: unionBoth

      unionByChr.ord leaves: 65
      unionByOrd.chr leaves: 'B'

      "'chr' is defined first, therefore, it is used rather
       than 'ord'"
      unionBoth.chr leaves: 'A'
      unionBoth.ord leaves: 65
      ```
      END
      ) do |_, stack|
        form = stack.drop.a(StructLayoutForm)
        block = stack.drop.a(Block)
        layout = form.layout
        view = layout.union.make!
        had_entry = false
        layout.each_desc_with_index do |desc|
          entry = block.entry_for? Word.new(desc.id)
          if entry
            view[desc.id] = desc.type.from(entry.form)
            had_entry = true
            break
          end
        end
        unless had_entry
          block.die("block must have one of the union's fields defined")
        end
        StructViewForm.new(view).onto(stack)
      end

      target.at("ffi:asUnion", <<-END
      ( Pd Slf -- Uv ): wraps Pointer decimal in a Union view
       according to the given Struct layout form.

      This word is **unsafe**: it does not check whether Pointer
      decimal points at something that is layed out according to
      Struct layout form. Passing 0 for Pointer decimal will lead
      to segfault. Passing a pointer that points outside of your
      program's memory will lead to segfault. Passing a pointer
      that *is* in the bounds of your program's memory, but one
      not pointing at a struct in accordance to Struct layout form,
      will lead to undefined behavior (most likely junk values
      in Union view). Showing ill-formed results of this word to
      clients may expose your program to a whole class of
      security vulnerabilities.

      ```
      [ chr char
        ord u8
      ] ffi:createLayout $: quux

      'A' $: chr

      this quux ffi:buildUnion $: quuxUnion

      quuxUnion ffi:addressof $: addr

      addr quux ffi:asUnion $: addrUnion
      addrUnion.chr leaves: 'A'
      addrUnion.ord leaves: 65
      ```
      END
      ) do |_, stack|
        layout_form = stack.drop.a(StructLayoutForm)
        pointer = stack.drop.a(Decimal)
        view = Novika::FFI::UnionView.new(layout_form.layout, Pointer(Void).new(pointer.to_u64))
        StructViewForm.new(view).onto(stack)
      end

      target.at("ffi:hole") do |engine, stack|
        typename = stack.drop.a(Word | Hole)
        type =
          case typename
          in Hole then Novika::FFI::UntypedPointer.new(typename.address)
          in Word then Novika::FFI::ValueTypeParser.new(engine.block, typename).parse
          end

        Hole.new(type).onto(stack)
      end

      target.at("ffi:box") do |engine, stack|
        typename = stack.drop.a(Word)
        form = stack.drop
        type = Novika::FFI::ValueTypeParser.new(engine.block, typename).parse
        pointer = type.from(form).box

        Decimal.new(pointer.address).onto(stack)
      end

      target.at("ffi:unbox") do |engine, stack|
        typename = stack.drop.a(Word)
        pointer = stack.drop.a(Decimal)
        type = Novika::FFI::ValueTypeParser.new(engine.block, typename).parse

        # TODO: document how unsafe this method is!

        # type != nothing => never nil
        type.unbox(Pointer(Void).new(pointer.to_u64)).to_form?.not_nil!.onto(stack)
      end

      target.at("ffi:unsafeWrite") do |engine, stack|
        typename = stack.drop.a(Word)
        form = stack.drop
        address = stack.drop.a(Decimal)

        # TODO: document how unsafe this method is!
        type = Novika::FFI::ValueTypeParser.new(engine.block, typename).parse
        value = type.from(form)
        value.write_to!(Pointer(Void).new(address.to_u64))
      end

      target.at("ffi:viewLayout") do |_, stack|
        view = stack.drop.a(StructViewForm)
        view.layout.onto(stack)
      end

      target.at("ffi:sizeof") do |engine, stack|
        typename = stack.drop.a(Word)
        type = Novika::FFI::ValueTypeParser.new(engine.block, typename).parse
        Decimal.new(type.sizeof).onto(stack)
      end

      target.at("ffi:addressof") do |engine, stack|
        foreign = stack.drop.a(Hole | StructViewForm)
        Decimal.new(foreign.address).onto(stack)
      end
    end
  end
end
