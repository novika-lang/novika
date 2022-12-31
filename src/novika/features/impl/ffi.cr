module Novika::Features::Impl
  class FFI
    include Feature

    def self.id : String
      "ffi"
    end

    def self.purpose : String
      "words for working with foreign functions and structs"
    end

    def self.on_by_default? : Bool
      true
    end

    def inject(into target : Block)
      target.at("library?", <<-END
      ( F -- true/false ): leaves whether Form is a library form.

      ```
      'foo' ffi:getLibrary library? leaves: true
      ```
      END
      ) { |_, stack| Boolean[stack.drop.is_a?(Library)].onto(stack) }

      target.at("ffi:getLibrary") do |engine, stack|
        id = stack.drop.a(Quote)
        unless library = engine.bundle.get_library?(id.string)
          id.die("no such library")
        end
        library.onto(stack)
      end

      target.at("ffi:createLayout") do |engine, stack|
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

      {% for method, desc in {inline: {"~", :InlineStruct}, reference: {"&", :StructReference}} %}
        {% sym, cls_prefix = desc %}

        target.at("ffi:allocateStruct{{sym.id}}") do |_, stack|
          form = stack.drop.a(StructLayoutForm)
          view = form.layout.{{method.id}}.make!
          StructViewForm.new(view).onto(stack)
        end

        target.at("ffi:buildStruct{{sym.id}}") do |_, stack|
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

        target.at("ffi:asStruct{{sym.id}}") do |_, stack|
          layout_form = stack.drop.a(StructLayoutForm)
          pointer = stack.drop.a(Decimal)
          # TODO: document how unsafe this method is!
          view = Novika::FFI::{{cls_prefix.id}}View.new(layout_form.layout, Pointer(Void).new(pointer.to_u64))
          StructViewForm.new(view).onto(stack)
        end
      {% end %}

      target.at("ffi:hole") do |engine, stack|
        typename = stack.drop.a(Word | Hole)
        case typename
        in Hole then type = Novika::FFI::UntypedPointer.new(typename.address)
        in Word
          type = Novika::FFI::ForeignType.parse(engine.block, typename, allow_nothing: false)
        end
        Hole.new(type).onto(stack)
      end

      target.at("ffi:box") do |engine, stack|
        typename = stack.drop.a(Word)
        form = stack.drop
        type = Novika::FFI::ForeignType.parse(engine.block, typename, allow_nothing: false)
        pointer = type.from(form).box

        Decimal.new(pointer.address).onto(stack)
      end

      target.at("ffi:unbox") do |engine, stack|
        typename = stack.drop.a(Word)
        pointer = stack.drop.a(Decimal)
        type = Novika::FFI::ForeignType.parse(engine.block, typename, allow_nothing: false)

        # TODO: document how unsafe this method is!

        # type != nothing => never nil
        type.unbox(Pointer(Void).new(pointer.to_u64)).to_form?.not_nil!.onto(stack)
      end

      target.at("ffi:viewLayout") do |_, stack|
        view = stack.drop.a(StructViewForm)
        view.layout.onto(stack)
      end

      target.at("ffi:sizeof") do |engine, stack|
        typename = stack.drop.a(Word)
        type = Novika::FFI::ForeignType.parse(engine.block, typename)
        Decimal.new(type.sizeof).onto(stack)
      end

      target.at("ffi:addressof") do |engine, stack|
        foreign = stack.drop.a(Hole | StructViewForm)
        Decimal.new(foreign.address).onto(stack)
      end
    end
  end
end