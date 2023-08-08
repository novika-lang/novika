module Novika::Capabilities::Impl
  class Essential
    include Capability

    def self.id : String
      "essential"
    end

    def self.purpose : String
      "exposes essential native code vocabulary, such as 'hydrate' and 'new'"
    end

    def self.on_by_default? : Bool
      true
    end

    def inject(into target)
      target.at(Word.new("true"), True.new)
      target.at(Word.new("false"), False.new)

      # TODO: example
      target.at("prototype", <<-END
      ( B -- P ): leaves the Prototype of Block.
      END
      ) do |_, stack|
        block = stack.drop.a(Block)
        block.prototype.onto(stack)
      end

      # TODO: example
      target.at("parent", <<-END
      ( B -- P ): leaves the Parent of Block.
      END
      ) do |_, stack|
        block = stack.drop.a(Block)
        block.die("no parent for block") unless parent = block.parent?
        parent.onto(stack)
      end

      target.at("address", "( B -- A ): leaves pointer Address of Block.") do |_, stack|
        block = stack.drop.a(Block)

        Decimal.new(block.object_id).onto(stack)
      end

      target.at("conts", "( -- Cb ): pushes the Continuations block.") do |engine, stack|
        engine.conts.onto(stack)
      end

      target.at("cont", "( -- Cb ): pushes the Continuation block.") do |engine, stack|
        engine.cont.onto(stack)
      end

      # TODO: example
      target.at("newContinuation", <<-END
      ( S B -- C ): creates a Continuation from a Stack and
       a Block.
      END
      ) do |_, stack|
        Engine.cont(
          block: stack.drop.a(Block),
          stack: stack.drop.a(Block)
        ).onto(stack)
      end

      target.at("getContBlock", <<-END
      ( C -- Cb ): leaves the Code block of a Continuation.
      END
      ) do |_, stack|
        cont = stack.drop.a(Block)
        cont.at(Engine::C_BLOCK_AT).onto(stack)
      end

      target.at("getContStack", <<-END
      ( C -- Sb ): leaves the Stack block of a Continuation.
      END
      ) do |_, stack|
        cont = stack.drop.a(Block)
        cont.at(Engine::C_STACK_AT).onto(stack)
      end

      target.at("this", <<-END
      ( -- B ): pushes the Block it's opened in.

      ```
      [ this ] open echo
      "STDOUT: [ this ]⏎ (instance of `[ this ]`)"
      ```
      END
      ) do |engine, stack|
        engine.block.onto(stack)
      end

      target.at("stack", <<-END
      ( -- S ): pushes the Stack it's opened in.

      ```
      stack dup echo
      "STDOUT: [ ⭮ ]⏎"

      'foo' <<
      stack echo
      "STDOUT: [ ⭮ 'foo' ]⏎"
      ```
      END
      ) do |_, stack|
        stack.onto(stack)
      end

      target.at("ahead", <<-END
      ( -- B ): leaves the block that will be executed after
       `this` finishes.

      ```
      100 [ ahead 1 inject ] open + leaves: 101 "(i.e. 100 1 +)"
      ```
      END
      ) do |engine, stack|
        cont = engine.conts.at(engine.conts.count - 2)
        cont = cont.as?(Block) || cont.die("malformed continuation")
        ahead = cont.at(Engine::C_BLOCK_AT)
        ahead.onto(stack)
      end

      target.at("resume", <<-END
      ( B -- ): closes blocks all the way up to, but not
       including, Block.
      END
      ) do |engine, stack|
        block = stack.drop.a(Block)
        conts = engine.conts
        found = false

        # This can be and probably should be a count decrement,
        # not tens of sequential drops. But we don't have that
        # level of control currently.
        until conts.tape.empty? || (found = block.same?(engine.block))
          conts.drop
        end

        block.die("resume: no such block in continuations") unless found
      end

      target.at("dup", <<-END
      ( F -- F F ): duplicates the Form before cursor.

      ```
      'hello' dup leaves: [ 'hello' 'hello' ]

      [ 1 2 | 3 ] $: block
      block [ dup ] hydrate
      block leaves: [ [ 1 2 2 | 3 ] ]
      ```
      END
      ) { |_, stack| stack.dupe }

      target.at("drop", <<-END
      ( F -- ): drops the Form before cursor.

      ```
      'hello' drop leaves: [ ]

      [ 1 2 | 3 ] $: block
      block [ drop ] hydrate
      block leaves: [ [ 1 | 3 ] ]
      ```
      END
      ) { |_, stack| stack.drop }

      target.at("swap", <<-END
      ( A B -- B A ): swaps two Forms before cursor.

      ```
      1 2 swap leaves: [ 2 1 ]

      [ 1 2 | 3 ] $: block
      block [ swap ] hydrate
      block leaves: [ [ 2 1 | 3 ] ]
      ```
      END
      ) { |_, stack| stack.swap }

      # TODO: example
      target.at("hydrate", <<-END
      ( S F -- ): opens (evaluates) Form with Stack set as the
       active stack. If Form is not a block, it is added to
       Stack (equivalent to `<<`), If Form is a block, its
       instance is opened. To open a block without creating
       an instance of it (unsafe), use `hydrate!`.
      END
      ) do |engine, stack|
        form = stack.drop
        new_stack = stack.drop.a(Block)
        engine.schedule(form, new_stack)
      end

      target.at("hydrate!", <<-END
      ( S F -- ): opens (evaluates) Form with Stack set as the
       active stack. If Form is not a block, the behavior is
       the same as in `hydrate`. If Form is a block, performs
       unsafe hydration (hydrates without making an instance
       of the block). For a safer alternative, see `hydrate`.
       Use if you know what you're doing, or if you're ready
       to make an instance yourself.

      Details: `hydrate!` is considered unsafe because hydration
      artifacts are exposed to the user and/or its blocks. The
      contents of a block after hydration may differ from its
      contents before unsafe hydration. Indeed, `hydrate!` is
      almost as unsafe as pushing into `conts`; the only benefit
      it provides is that it is able to catch infinite/very
      deep recursion.
      END
      ) do |engine, stack|
        form = stack.drop
        new_stack = stack.drop.a(Block)
        engine.schedule!(form, new_stack)
      end

      target.at("open", <<-END
      ( F -- F' ): opens Form in the active stack. Equivalent
       to `stack F hydrate`.

      ```
      100 open leaves: 100

      1 [ 2 + ] open leaves: 3
      ```
      END
      ) do |engine, stack|
        form = stack.drop
        engine.schedule(form, stack)
      end

      target.at("there", <<-END
      ( S B -- S ): opens Block with Stack set as the active
       stack. Leaves Stack. Ahead is transferred to block.

      ```
      [ 1 2 ] [ + ] there leaves: [ [ 3 ] ]
      [ 1 2 ] [ ahead thruBlock open ] there + leaves: [ [ 3 ] ]
      ```
      END
      ) do |engine, stack|
        form = stack.drop
        new_stack = stack.top.a(Block)
        engine.schedule(form, new_stack)
      end

      target.at("do", <<-END
      ( F -- ): opens Form with an empty stack activated, and
       disposed when Form has been evaluated.

      ```
      [ 'Hi!' echo ] do
      "STDOUT: Hi!⏎"
      ```
      END
      ) do |engine, stack|
        form = stack.drop
        engine.schedule(form, Block.new)
      end

      target.at("new", "( B -- I ): leaves an Instance of a Block.") do |_, stack|
        block = stack.drop.a(Block)
        block.instance.onto(stack)
      end

      target.at("shallowNew", <<-END
      ( B -- Si ): leaves a Shallow instance of Block.

      `shallowNew` is different from `new` in that it does not reparent
      sub-blocks to the parent instance recursively. Instead, it only
      creates an instance of Block, and does not look at skips its
      content entirely.

      ```
      [ $: x [ x ] ] @: newBox

      1 newBox $: fooBox1
      2 newBox $: fooBox2
      3 newBox $: fooBox3

      fooBox1 open leaves: 1
      fooBox2 open leaves: 2
      fooBox3 open leaves: 3

      [ fooBox1 fooBox2 fooBox3 ] vals $: boxes

      boxes shallowNew $: shallowBoxesInstance
      shallowBoxesInstance 0 fromLeft open leaves: 1
      shallowBoxesInstance 1 fromLeft open leaves: 2
      shallowBoxesInstance 2 fromLeft open leaves: 3

      "Works as expected! Note that sub-blocks are exactly the same as
       those in the original 'boxes' block. However, 'shallowBoxesInstance'
       and 'boxes' are different blocks now:"

      (shallowBoxesInstance 0 fromLeft) (boxes 0 fromLeft) same? leaves: true
      (shallowBoxesInstance 1 fromLeft) (boxes 1 fromLeft) same? leaves: true
      (shallowBoxesInstance 2 fromLeft) (boxes 2 fromLeft) same? leaves: true

      boxes shallowBoxesInstance same? leaves: false

      "... and 'shallowBoxesInstance' does indeed have 'boxes' as its parent:"

      (shallowBoxesInstance parent) boxes same? leaves: true
      ```
      END
      ) do |_, stack|
        block = stack.drop.a(Block)
        block.instance(shallow: true).onto(stack)
      end

      target.at("sel", <<-END
      ( D A B -- A/B ): selects A (Determiner is truthy) or B
       (Determiner is falsey)
      END
      ) do |_, stack|
        b = stack.drop
        a = stack.drop
        det = stack.drop
        det.sel(a, b).onto(stack)
      end

      target.at("br", <<-END
      ( D T F -- ? ): opens True/False forms depending on
       Determiner being true/false.
      END
      ) do |engine, stack|
        b = stack.drop
        a = stack.drop
        det = stack.drop
        engine.schedule(det.sel(a, b), stack)
      end

      target.at("<", <<-END
      ( A B -- S ): leaves whether A is smaller than (less than) B.
      END
      ) do |_, stack|
        b = stack.drop.a(Decimal)
        a = stack.drop.a(Decimal)
        Boolean[a < b].onto(stack)
      end

      target.at("same?", <<-END
      ( F1 F2 -- true/false ): leaves whether two Forms are the
       same (by reference for block, by value for any other form).

      ```
      1 2 same? leaves: false
      1 1 same? leaves: true

      'hello' 'hello world' same? leaves: false
      'hello' 'hello' same? leaves: true

      "etc..."

      [ 1 2 + ] $: b1
      [ 1 2 + ] $: b2

      b1 b2 same? leaves: false "They're different blocks, content doesn't matter!"

      b1 b1 same? leaves: true
      b2 b2 same? leaves: true
      ```
      END
      ) do |_, stack|
        b = stack.drop
        a = stack.drop
        Boolean.same?(a, b).onto(stack)
      end

      target.at("=", <<-END
      ( F1 F2 -- true/false ): leaves whether two Forms are equal by
       content (they may or may not be the same forms reference-wise,
       i.e., those for which `same?` would leave true).

      ```
      1 2 = leaves: false
      1 1 = leaves: true

      'hello' 'hello world' = leaves: false
      'hello' 'hello' = leaves: true

      "etc..."

      [ 1 2 + ] $: b1
      [ 1 2 + ] $: b2

      b1 b2 = leaves: true "They're equal by content!"

      b1 b1 = leaves: true
      b2 b2 = leaves: true

      "Supports self-reference:"
      [ ] $: b3
      b3 b3 shove
      b3 b3 = leaves: true
      (b3 first) b3 = leaves: true
      "etc..."
      ```
      END
      ) do |_, stack|
        b = stack.drop
        a = stack.drop
        Boolean[a == b].onto(stack)
      end

      target.at("anyof?", <<-END
      ( F B -- true/false ): leaves whether any form in Block is
       equal (via `=`) to Form.

      ```
      1 [ 1 2 3 ] anyof? leaves: true
      'hello' [ 'hello' 'world' 1 ] anyof? leaves: true
      'hello' [ 1 2 3 ] anyof? leaves: false
      ```
      END
      ) do |_, stack|
        block = stack.drop.a(Block)
        form = stack.drop
        Boolean[form.in?(block)].onto(stack)
      end

      target.at("occurrences", <<-END
      ( B/Q Pf/Pq -- Bi ): leaves Begin indices of all occurrences
       of Pattern form/Pattern quote in Block/Quote. Begin indices
       is an orphan with no entries.

      Works in a similar way to `anyof?` in that it compares each
      element of the Block/Quote with Pattern form/Pattern quote
      like `=` (but not using `=`, at least in the quote case
      where KMP is used).

      ```
      [ ] 123 occurrences leaves: [ [ ] ]

      [ 1 1 2 0 0 1 2 1 3 4 8 ] $: haystack
      haystack 0 occurrences leaves: [ [ 3 4 ] ]
      haystack 1 occurrences leaves: [ [ 0 1 5 7 ] ]
      haystack 'foo' occurrences leaves: [ [ ] ]

      '' 'foobar' occurrences leaves: [ [ ] ]
      'foobar' '' occurrences leaves: [ [ ] ]

      'foobra' $: haystack
      haystack 'o' occurrences leaves: [ [ 1 2 ] ]
      haystack 'foo' occurrences leaves: [ [ 0 ] ]
      haystack 'ra' occurrences leaves: [ [ 4 ] ]

      'GATCCATATG' $: haystack
      haystack 'ATAAT' occurrences leaves: [ [ ] ]
      haystack 'ATAT' occurrences leaves: [ [ 5 ] ]
      ```
      END
      ) do |_, stack|
        pattern = stack.drop
        iterable = stack.drop.a(Block | Quote)

        case iterable
        in Quote
          fail = iterable.empty? || (pattern.is_a?(Quote) && pattern.empty?)
        in Block
          fail = iterable.count.zero?
        end

        if fail
          Block.new.onto(stack)
          next
        end

        occurrences = [] of Form
        iterable.each_occurrence_of(pattern) do |index|
          occurrences << Decimal.new(index)
        end

        Block.with(occurrences, leaf: false).onto(stack)
      end

      target.at("uppercase?", <<-END
      ( Q -- true/false ): leaves whether Quote is all-uppercase.
       If Quote is empty, leaves false.

      ```
      '' uppercase? leaves: false
      'A' uppercase? leaves: true
      'hello' uppercase? leaves: false
      'Hello' uppercase? leaves: false
      'HELLO' uppercase? leaves: true
      'HELLO WORLD' uppercase? leaves: false
      ```
      END
      ) do |_, stack|
        quote = stack.drop.a(Quote)
        string = quote.string

        case string.size
        when 0
          isup = false
        when 1
          isup = string[0].uppercase?
        else
          isup = true
          string.each_char do |char|
            unless char.uppercase?
              isup = false
              break
            end
          end
        end

        Boolean[isup].onto(stack)
      end

      target.at("toUppercase", <<-END
      ( Q -- Uq ): leaves all- Uppercase quote for Quote: converts
       lowercase character(s) in Quote to uppercase. If Quote is empty,
       leaves empty quote.

      ```
      '' toUppercase leaves: ''
      'hello' toUppercase leaves: 'HELLO'
      'hello world' toUppercase? leaves: 'HELLO WORLD'
      ```
      END
      ) do |_, stack|
        quote = stack.drop.a(Quote)
        Quote.new(quote.string.upcase).onto(stack)
      end

      # TODO: example
      target.at("block?", <<-END
      ( F -- true/false ): leaves whether Form is a block.
      END
      ) do |_, stack|
        Boolean[stack.drop.is_a?(Block)].onto(stack)
      end

      target.at("asBlock", <<-END
      ( F -- B ): asserts that Form is a Block, dies if it's not.

      For example, the following expression dies:

      ```
      100 asBlock
      ```

      Et cetera for all other forms, except:

      ```
      [] asBlock leaves: [ [] "(the same block)" ]
      ```
      END
      ) { |_, stack| stack.top.a(Block) }

      target.at("word?", <<-END
      ( F -- true/false ): leaves whether Form is a word form,
       or a block that implements '__word__'.

      ```
      #foo word? leaves: true

      [ #foo $: __word__ this ] open word? leaves: true
      ```
      END
      ) do |_, stack|
        form = stack.drop
        Boolean[form.is_a?(Word) || (form.is_a?(Block) && form.can_be?(Word))].onto(stack)
      end

      target.at("private?", <<-END
      ( W -- true/false ): leaves whether Word is private (by convention).

      A Word prefixed by one or more underscores '_' *but that which
      does not end with one(s)* is considered private by convention.
      Hook words such as `__quote__` are *not* considered private.

      The fact that privacy is defined "by convention" means that nothing
      actually stops anyone from obtaining the word's associated value form.

      ```
      #hello private? leaves: false
      #_hello private? leaves: true
      #_ private? leaves: false "Beware!"
      ```
      END
      ) do |_, stack|
        Boolean[stack.drop.a(Word).private?].onto(stack)
      end

      target.at("toWord", <<-END
      ( F -- W ): converts Form into Word.
        1. If Form is a word, behaves as noop
        2. If Form is a quote, dies only if quote contains
           Unicode whitespace characters or is itself empty.
        3. If Form is a quoted word, peels off **all** quoting
      END
      ) do |_, stack|
        form = stack.drop.a(Word | QuotedWord | Quote)

        case form
        in Word       then form.onto(stack)
        in QuotedWord then form.to_word.onto(stack)
        in Quote
          string = form.string
          if string.empty?
            form.die("toWord: quote argument is empty")
          elsif string.each_char.any?(&.whitespace?)
            form.die("toWord: quote argument contains whitespace")
          end
          Word.new(form.string).onto(stack)
        end
      end

      target.at("asWord", <<-END
      ( F -- W ): asserts that Form is a Word form, dies if
       it's not.

      For example, the following expression dies:

      ```
      100 asWord
      ```

      Et cetera for all other forms, except:

      ```
      #foo asWord leaves: [ foo ]
      ```

      `__word__` hook can make a block usable in place of a word,
      provided its definition leaves a word or a block which
      implements '__word__':

      ```
      [ $: x x $: __word__ this ] @: a
      #foo a asWord "beware: leaves instance of a"
      #boo a a asWord "beware: leaves instance of a"
      ```
      END
      ) { |_, stack| stack.top.a(Word) }

      target.at("quotedWord?", <<-END
      ( F -- true/false ): leaves whether Form is a quoted word
       form, or a block that implements '__quotedWord__'.

      ```
      ##foo quotedWord? leaves: true
      [ ##foo $: __quotedWord__ this ] open quotedWord? leaves: true
      ```
      END
      ) do |_, stack|
        form = stack.drop
        Boolean[form.is_a?(QuotedWord) || (form.is_a?(Block) && form.can_be?(QuotedWord))].onto(stack)
      end

      target.at("asQuotedWord", <<-END
      ( F -- Qw ): asserts that Form is a Quoted word form,
       dies if it's not.

      For example, the following expression dies:

      ```
      100 asQuotedWord
      ```

      Et cetera for all other forms, except:

      ```
      ##foo asQuotedWord leaves: #foo
      ```

      `__quotedWord__` hook can make a block usable in place of
      a quoted word, provided its definition leaves a quoted
      word or a block that implements `__quotedWord__`:

      ```
      [ $: x x $: __quotedWord__ this ] @: a
      ##foo a asQuotedWord "beware: leaves instance of a"
      ##boo a a asQuotedWord "beware: leaves instance of a"
      ```
      END
      ) { |_, stack| stack.top.a(QuotedWord) }

      target.at("decimal?", <<-END
      ( F -- true/false ): leaves whether Form is a decimal form,
       or a block that implements '__decimal__'.

      ```
      123 decimal? leaves: true
      [ 123 $: __decimal__ this ] open decimal? leaves: true
      ```
      END
      ) do |_, stack|
        form = stack.drop
        Boolean[form.is_a?(Decimal) || (form.is_a?(Block) && form.can_be?(Decimal))].onto(stack)
      end

      target.at("toQuotedWord", <<-END
      ( Qw/W -- #Qw/#W ): adds a layer of "quoting" to Quoted
       word or Word.

      ```
      "Note that in quoted word literals (here on the left hand
       side) one layer of quoting is 'eaten off' by the parser!"

      #foo toQuotedWord leaves: #foo
      ##foo toQuotedWord leaves: ##foo
      ```
      END
      ) do |_, stack|
        form = stack.drop.a(Word | QuotedWord)
        form.to_quoted_word.onto(stack)
      end

      target.at("asDecimal", <<-END
      ( F -- D ): asserts that Form is a Decimal form, dies if
       it's not.

      For example, the following expression dies:

      ```
      'foo' asDecimal
      ```

      Et cetera for all other forms, except:

      ```
      100 asDecimal leaves: 100
      ```

      `__decimal__` hook can make a block usable in place of a
      decimal, provided its definition leaves a decimal or a
      block that implements `__decimal__`:

      ```
      [ $: x x $: __decimal__ this ] @: a
      100 a asDecimal "beware: leaves an instance of a"
      200 a a asDecimal "beware: leaves an instance of a"
      ```
      END
      ) { |_, stack| stack.top.a(Decimal) }

      target.at("quote?", <<-END
      ( F -- true/false ): leaves whether Form is a quote form,
       or a block that implements '__quote__'.

      ```
      'foo' quote? leaves: true
      [ 'foo' $: __quote__ this ] open quote? leaves: true
      ```
      END
      ) do |_, stack|
        form = stack.drop
        Boolean[form.is_a?(Quote) || (form.is_a?(Block) && form.can_be?(Quote))].onto(stack)
      end

      target.at("asQuote", <<-END
      ( F -- Q ): asserts that Form is a Quote form, dies if
       it's not.

      For example, the following expression dies:

      ```
      100 asQuote
      ```

      Et cetera for all other forms, except:

      ```
      'foo' asQuote leaves: 'foo'
      ```

      `__quote__` hook can make a block usable in place of a
      quote, provided its definition leaves a quote or a block
      that implements `__quote__`:

      ```
      [ $: x x $: __quote__ this ] @: a
      'foo' a asQuote "beware: leaves instance of a"
      'boo' a a asQuote "beware: leaves instance of a"
      ```
      END
      ) { |_, stack| stack.top.a(Quote) }

      target.at("boolean?", <<-END
      ( F -- true/false ): leaves whether Form is a boolean form,
       or a block that implements '__boolean__'.

      ```
      true boolean? leaves: true
      [ true $: __boolean__ this ] open boolean? leaves: true
      ```
      END
      ) do |_, stack|
        form = stack.drop
        Boolean[form.is_a?(Boolean) || (form.is_a?(Block) && form.can_be?(Boolean))].onto(stack)
      end

      target.at("asBoolean", <<-END
      ( F -- B ): asserts that Form is a Boolean form, dies if
       it's not.

      For example, the following expression dies:

      ```
      100 asBoolean
      ```

      Et cetera for all other forms, except:

      ```
      true asBoolean leaves: true
      false asBoolean leaves: false
      ```

      `__boolean__` hook can make a block usable in place of a
      boolean, provided its definition leaves a boolean or a
      block that implements `__boolean__`:

      ```
      [ $: x x $: __boolean__ this ] @: a
      true a asBoolean "beware: leaves an instance of a"
      true a a asBoolean "beware: leaves an instance of a"
      ```
      END
      ) { |_, stack| stack.top.a(Boolean) }

      target.at("builtin?", "( F -- true/false ): leaves whether Form is a builtin form.") do |_, stack|
        Boolean[stack.drop.is_a?(Builtin)].onto(stack)
      end

      target.at("asBuiltin", <<-END
      ( F -- B ): asserts Form is a Builtin, dies if it's not.

      For example, the following expression dies:

      ```
      'foo' asBuiltin
      ```

      Et cetera for all other forms, except:

      ```
      #+ here asBuiltin toQuote leaves: '[ native code ]'
      ```
      END
      ) { |_, stack| stack.top.a(Builtin) }

      target.at("color?", <<-END
      ( F -- true/false ): leaves whether Form is a color form,
       or a block that implements '__color__'.

      ```
      0 0 0 rgb color? leaves: true
      [ 0 0 0 rgb $: __color__ this ] open color? leaves: true
      ```
      END
      ) do |_, stack|
        form = stack.drop
        Boolean[form.is_a?(Color) || (form.is_a?(Block) && form.can_be?(Color))].onto(stack)
      end

      target.at("asColor", <<-END
      ( F -- C ): asserts that Form is a Color form, dies if
       it's not.

      For example, the following expression dies:

      ```
      100 asColor
      ```

      Et cetera for all other forms, except:

      ```
      0 0 0 rgb asColor toQuote leaves: 'rgb(0, 0, 0)'
      ```

      `__color__` hook can make a block usable in place of a
      color, provided its definition leaves a color or a block
      that implements `__color__`:

      ```
      [ $: x x $: __color__ this ] @: a
      0 0 0 rgb a asColor "beware: leaves an instance of a"
      0 0 0 rgb a a asColor "beware: leaves an instance of a"
      ```
      END
      ) { |_, stack| stack.top.a(Color) }

      target.at("byteslice?", <<-END
      ( F -- true/false ): leaves whether Form is a byteslice
       form, or a block that implements '__byteslice__'.

      ```
      'hello world' toByteslice byteslice? leaves: true
      [ [ 'Hi!' toByteslice ] $: __byteslice__ this ] open byteslice? leaves: true
      ```
      END
      ) do |_, stack|
        form = stack.drop
        Boolean[form.is_a?(Byteslice) || (form.is_a?(Block) && form.can_be?(Byteslice))].onto(stack)
      end

      target.at("asByteslice", <<-END
      ( F -- B ): asserts that Form is a Byteslice form, dies if
       it's not.

      For example, the following expression dies:

      ```
      100 asByteslice
      ```

      Et cetera for all other forms, except:

      ```
      'hello world' toByteslice asByteslice leaves: '[byteslice, consists of 11 mutable byte(s)]'
      ```

      `__byteslice__` hook can make a block usable in place of
      a byteslice, provided its definition leaves a byteslice
      or a block that implements `__byteslice__`:

      ```
      [ $: x x $: __byteslice__ this ] @: a
      'foo' toByteslice a asByteslice "beware: leaves an instance of a"
      'foo' toByteslice a a asByteslice "beware: leaves an instance of a"
      ```
      END
      ) { |_, stack| stack.top.a(Byteslice) }

      target.at("pushes", <<-END
      ( B N F -- ): creates a definition for Name in Block that
       pushes Form when resolved there.
      END
      ) do |_, stack|
        form = stack.drop
        name = stack.drop
        block = stack.drop.a(Block)
        block.at name, Entry.new(form)
      end

      target.at("opens", <<-END
      ( B N F -- ): creates a definition for Name in Block that
       opens Form when resolved there.
      END
      ) do |_, stack|
        form = stack.drop
        name = stack.drop
        block = stack.drop.a(Block)
        block.at name, OpenEntry.new(form)
      end

      target.at("entry:submit", <<-END
      ( Ss N F -- ): replaces the value form of an existing
       definition for Name in Submittable store (usually a block)
       to Form. Does not change whether the definition opens
       or pushes.

      ```
      [ 'John Doe' $: fullName
        [ fullName count ] @: fullNameLength
      ] obj $: person

      person.fullName leaves: 'John Doe'
      person.fullNameLength leaves: 8

      "Let's try to change the name:"
      person #fullName 'Alice Bobette' entry:submit
      person.fullName leaves: 'Alice Bobette'
      person.fullNameLength leaves: 13

      "Now let's change the way we compute the length; let's count
       how many double-Ts there are in the full name."
      person #fullNameLength [ person.fullName 'tt' occurrences count ] entry:submit

      "... just one:"
      person.fullNameLength leaves: 1

      "... or maybe multiple:"
      person #fullName 'Tette Mopettitte' entry:submit
      person.fullName leaves: 'Tette Mopettitte'
      person.fullNameLength leaves: 3
      ```
      END
      ) do |_, stack|
        form = stack.drop
        name = stack.drop
        submittable = stack.drop.a(ISubmittableStore)
        submittable.submit(name, form)
      end

      target.at("entry:exists?", <<-END
      ( Rs N -- true/false ): leaves whether Readable store
       (usually a block) can fetch value for Name.

      ```
      [ orphan $: table
        orphan extendWith: [
          [ ${ name age score }
            [ name $: name
              age  $: age ] obj toDict $: record
            table record score pushes
          ] @: set
          [ ${ name age } table (this toDict) entry:fetch ] @: get
          [ ${ name age } table (this toDict) entry:exists? ] @: has?
          [ table entry:names map: [ $: record
              [
                record.name (31 ' ' lpad) (31 '...' fit)
                record.age toQuote (15 ' ' lpad) (15 '...' fit)
                (table record entry:fetch) toQuote (16 ' ' lpad) (16 '...' fit)
              ] vals sepBy: ' |'
            ] sepBy: '\n'
          ] @: __quote__
        ]
      ] @: newScoreboard

      newScoreboard $: scoreboard

      'John Doe' 42 '100 points' scoreboard.set
      'Johnanna Doe' 28 '170 points' scoreboard.set
      'Alice H.' 19 '250 points' scoreboard.set
      'David A.' 67 '90 points' scoreboard.set

      scoreboard echo

      """STDOUT:
                       John Doe |             42 |      100 points⏎
                   Johnanna Doe |             28 |      170 points⏎
                       Alice H. |             19 |      250 points⏎
                       David A. |             67 |       90 points⏎
      """

      'John Doe' 42 scoreboard.get leaves: '100 points'
      'Alice H.' 19 scoreboard.get leaves: '250 points'

      'David A.' 67 scoreboard.has? leaves: true
      'David A.' 123 scoreboard.has? leaves: false
      'Peter Peterson' 19 scoreboard.has? leaves: false
      ```
      END
      ) do |_, stack|
        name = stack.drop
        store = stack.drop.a(IReadableStore)
        Boolean[store.has_form_for?(name)].onto(stack)
      end

      target.at("entry:fetch", <<-END
      ( Rs N -- F ): leaves the value Form with the given Name
       in Readable store (usually a block). Does not open the
       value form. Dies if Store does not contain an entry
       for Name.
      END
      ) do |_, stack|
        name = stack.drop
        store = stack.drop.a(IReadableStore)
        store.form_for(name).onto(stack)
      end

      target.at("entry:fetch?", <<-END
      ( Rs N -- F true / false ): leaves the value Form with the
       given Name in Readable store (usually a block) if an entry
       for Name exists there, and/or a boolean indicating the
       latter: `true` (exists), or `false` (does not exist).

      ```
      [ ] $: a
      a #x 100 pushes

      a #x entry:fetch? leaves: [ 100 true ]
      a #y entry:fetch? leaves: [ false ]
      ```
      END
      ) do |_, stack|
        name = stack.drop
        store = stack.drop.a(IReadableStore)
        if form = store.form_for?(name)
          form.onto(stack)
        end
        Boolean[!!form].onto(stack)
      end

      target.at("entry:open", <<-END
      ( Rs C N -- ... ): resolves Name in Readable store and *opens*
       it if it is an opener, assuming Caller to be the opener block.
      END
      ) do |_, stack|
        name = stack.drop.a(Word)
        caller = stack.drop.a(Block)
        store = stack.drop.a(IReadableStore)

        unless store.is_a?(Block)
          # There is no such thing as an "entry" in anything
          # other than block.
          form = store.form_for(name)
          form.onto(stack)
          next
        end

        entry = store.entry_for(name)
        if entry.is_a?(OpenEntry)
          caller.inject(Word.new("open"))
        end

        entry.onto(stack)
      end

      target.at("entry:flatFetch?", <<-END
      ( B N -- F true / false ): leaves the value Form under
       Name in Block's dictionary followed by `true`, or `false`
       if no such entry is in Block. Block hierarchy is not
       traversed (only the Block's own dictionary is looked at).
      END
      ) do |_, stack|
        name = stack.drop
        block = stack.drop.a(Block)
        if form = block.flat_at?(name)
          form.onto(stack)
        end
        Boolean[!!form].onto(stack)
      end

      target.at("entry:opener?", <<-END
      ( Rs N -- true/false ): leaves whether an entry with the
       given Name in Readable store (usually a block) is an
       opener entry. Dies if Readable store has no entry with
       the given Name.
      END
      ) do |_, stack|
        name = stack.drop
        store = stack.drop.a(IReadableStore)
        Boolean[store.opener?(name)].onto(stack)
      end

      target.at("entry:delete", <<-END
      ( B N -- ): removes the entry corresponding to Name form
       from the dictionary of Block if it exists there. Otherwise,
       does nothing.

      ```
      100 $: x

      [ 200 $: x ] obj $: foo

      "'x' of foo shadows 'x' of toplevel block"
      foo.x leaves: 200

      "Let's try to remove it so it doesn't:"
      foo #x entry:delete
      foo.x leaves: 100
      ```
      END
      ) do |_, stack|
        name = stack.drop
        block = stack.drop.a(Block)
        block.delete_entry(name)
      end

      target.at("entry:wipeout", <<-END
      ( B -- ): removes all *owned* dictionary entries in Block.

      ```
      [ 100 $: x
        200 $: y
      ] obj $: numbers

      numbers entry:names leaves: [ [x y] ]

      numbers entry:wipeout
      numbers entry:names leaves: [ [] ]
      ```
      END
      ) do |_, stack|
        block = stack.drop.a(Block)
        block.clear_entries
      end

      target.at("entry:pathTo?", <<-END
      ( B N -- P F true / false ): leaves Path, a block describing the
       path to Form (including Block itself) under the corresponding
       Name (like `entry:fetch?`). Follows Path and Form with `true`
       indicating success, otherwise *only* `false` indicating that
       there is no Form corresponding to Name in Block or any of the
       blocks reachable from Block.

      This word exists mainly for testing word lookup sanity. Feel free
      to use it if you find any reason to!

      ```
      [ 100 $: x  'a' $: __quote__ ] obj $: a
      [ 200 $: y  'b' $: __quote__ ] obj $: b
      [ 300 $: z  'c' $: __quote__ ] obj $: c

      a -- b -- c drop

      [ a #x entry:pathTo? ] vals sepBy: ' ' leaves: '[ a ] 100 true'
      [ b #x entry:pathTo? ] vals sepBy: ' ' leaves: '[ b a ] 100 true'
      [ c #x entry:pathTo? ] vals sepBy: ' ' leaves: '[ c b a ] 100 true'

      [ b #y entry:pathTo? ] vals sepBy: ' ' leaves: '[ b ] 200 true'
      [ c #y entry:pathTo? ] vals sepBy: ' ' leaves: '[ c b ] 200 true'

      [ c #z entry:pathTo? ] vals sepBy: ' ' leaves: '[ c ] 300 true'

      [ c #foo entry:pathTo? ] vals sepBy: ' ' leaves: 'false'
      ```
      END
      ) do |_, stack|
        name = stack.drop
        block = stack.drop.a(Block)

        unless result = block.path_to_entry?(name)
          Boolean[false].onto(stack)
          next
        end

        needle, path = result
        path.onto(stack)
        needle.onto(stack)
        Boolean[true].onto(stack)
      end

      target.at("entry:names", <<-END
      ( B -- Nb ): gathers all *owned* dictionary entry names of Block
       into Name block.

      ```
      [ 100 200 ${ x y } ] obj $: myParent
      [ 300 $: z ] obj $: myChild
      [ 'Hello World' $: greeting ] obj $: myFriend

      myParent -- myChild drop
      myParent ·> myFriend drop
      myChild ·> myFriend drop "for good measure :)"

      myParent entry:names leaves: [ [y x] ]
      myChild entry:names leaves: [ [z] ]
      myFriend entry:names leaves: [ [greeting] ]
      ```
      END
      ) do |_, stack|
        block = stack.drop.a(Block)
        result = Block.new
        block.each_entry_name do |form|
          result.add(form)
        end
        result.onto(stack)
      end

      target.at("entry:names*", <<-END
      ( B -- Nb ): gathers all dictionary entry names *reachable* from
       Block to Name block. That is, gathers all entry names in Block,
       Block's parents, Block's friends, and so on. Explores the entire
       relative graph of Block.

      Order is not guaranteed, and mainly depends on the appearance of
      Block's relative graph.

      ```
      [ 100 200 ${ x y } ] obj toOrphan $: myParent
      [ 300 $: z ] obj toOrphan $: myChild
      [ 'Hello World' $: greeting ] obj toOrphan $: myFriend

      myParent -- myChild drop
      myParent ·> myFriend drop
      myChild ·> myFriend drop

      myParent entry:names* leaves: [ [y x greeting] ]
      myChild entry:names* leaves: [ [z y x greeting] ]
      myFriend entry:names* leaves: [ [greeting] ]
      ```
      END
      ) do |_, stack|
        block = stack.drop.a(Block)
        names = [] of Form
        leaf = false
        block.each_relative_fetch do |relative|
          relative.each_entry_name do |name|
            names << name
            next if leaf
            leaf = name.is_a?(Block)
          end
          nil
        end
        names.uniq!
        Block.with(names, leaf).onto(stack)
      end

      target.at("entry:values", <<-END
      ( B -- Vb ): gathers all *owned* dictionary entry value forms of
       Block into Value block.

      ```
      [ 100 200 ${ x y } ] obj $: myParent
      [ 300 $: z ] obj $: myChild
      [ 'Hello World' $: greeting ] obj $: myFriend

      myParent -- myChild drop
      myParent ·> myFriend drop
      myChild ·> myFriend drop

      myParent entry:values leaves: [ [200 100] ]
      myChild entry:values leaves: [ [300] ]
      myFriend entry:values leaves: [ ['Hello World'] ]
      ```
      END
      ) do |_, stack|
        block = stack.drop.a(Block)
        result = Block.new
        block.each_entry_value do |form|
          result.add(form)
        end
        result.onto(stack)
      end

      target.at("entry:values*", <<-END
      ( B -- Nb ): gathers all dictionary entry values *reachable* from
       Block to Name block. That is, gathers all entry values in Block,
       Block's parents, Block's friends, and so on. Explores the entire
       relative graph of Block.

      Order is not guaranteed, and mainly depends on the appearance
      of Block's relative graph. Values may repeat if some blocks
      in this graph define entries with the same name.

      ```
      [ 100 200 ${ x y } ] obj toOrphan $: myParent
      [ 300 $: z ] obj toOrphan $: myChild
      [ 'Hello World' $: greeting ] obj toOrphan $: myFriend

      myParent -- myChild drop
      myParent ·> myFriend drop
      myChild ·> myFriend drop

      myParent entry:values* leaves: [ [200 100 'Hello World'] ]
      myChild entry:values* leaves: [ [300 200 100 'Hello World'] ]
      myFriend entry:values* leaves: [ ['Hello World'] ]
      ```
      END
      ) do |_, stack|
        block = stack.drop.a(Block)
        values = [] of Form
        leaf = false
        block.each_relative_fetch do |relative|
          relative.each_entry_value do |value|
            values << value
            next if leaf
            leaf = value.is_a?(Block)
          end
          nil
        end
        Block.with(values, leaf).onto(stack)
      end

      target.at("entry:count", <<-END
      ( B -- Ec ): leaves Entry count, that is, the amount of entries
       owned by (defined in) Block.

      ```
      [ 100 200 ${ x y } ] obj $: myBlock

      myBlock entry:count leaves: 2 "'x' and 'y'"
      ```
      END
      ) do |_, stack|
        block = stack.drop.a(Block)

        Decimal.new(block.entry_count).onto(stack)
      end

      target.at("shallowCopy", <<-END
      ( B -- C ): makes a shallow copy (sub-blocks are not copied)
       of Block's tape and dictionary, and leaves a Copy block with
       the tape copy, dictionary copy set as its tape, dictionary.

      ```
      [ 1 2 3 ] $: a
      a shallowCopy $: b
      a #x 0 pushes
      b #y 1 pushes
      b 1 shove
      a b 2echo
      "STDOUT: [ 1 2 3 · ${x :: 0} ]⏎"
      "STDOUT: [ 1 2 3 1 · ${y :: 1} ]⏎"
      ```
      END
      ) do |_, stack|
        stack.drop.a(Block).shallow.onto(stack)
      end

      target.at("resub", <<-END
      ( O B -- ): replaces the substrate of Block with Other's
       substrate. This is useful if you want to swap Block's
       contents with Other's without changing Block's identity:

      ```
      [ 1 2 3 ] $: a
      [ 'a' 'b' 'c' ] $: b
      b #x 0 pushes
      b echo
      "STDOUT: [ 'a' 'b' 'c' · ${x :: 0} ]⏎"

      a b resub
      b echo
      "STDOUT: [ 1 2 3 · ${x :: 0} ]⏎"
      ```

      Note that since *substrate* is replaced, not *tape*, the
      cursor position is saved:

      ```
      a b 2echo
      "STDOUT: [ 1 2 3 ]⏎"
      "STDOUT: [ 'a' 'b' 'c' · ${x :: 0} ]⏎"

      b 2 |-
      a b 2echo
      "STDOUT: [ 1 2 3 ]⏎"
      "STDOUT: [ 'a' | 'b' 'c' · ${x :: 0} ]⏎"

      a b resub
      b echo
      "STDOUT: [ 1 | 2 3 · ${x :: 0} ]⏎"
      ```
      END
      ) do |_, stack|
        block = stack.drop.a(Block)
        other = stack.drop.a(Block)
        block.resub(other)
      end

      target.at("fromLeft", <<-END
      ( B/Q/Bf I -- E ): leaves Index-th Element from the left
       in Block, Quote, or Byteslice form.

      ```
      [ 1 2 3 ] 0 fromLeft leaves: 1
      ```
      END
      ) do |_, stack|
        index = stack.drop.a(Decimal).posint
        form = stack.drop.a(Block | Quote | Byteslice)
        form.at(index.to_i).onto(stack)
      end

      target.at("fromRight", <<-END
      ( B/Q/Bf I -- E ): leaves Index-th Element from the right
       in Block, Quote, or Byteslice form.

      ```
      [ 1 2 3 ] 0 fromRight leaves: 3
      [ 1 2 3 ] 1 fromRight leaves: 2
      [ 1 2 3 ] 2 fromRight leaves: 1
      ```
      END
      ) do |_, stack|
        index = stack.drop.a(Decimal).posint
        form = stack.drop.a(Block | Quote | Byteslice)
        form.at(form.count - index.to_i - 1).onto(stack)
      end

      target.at("fromLeft*", <<-END
      ( B/Q/Bf N -- Eb/Rq/Rbf ): leaves Elements block (if given
       a Block), Result quote (if given a Quote), or Result
       byteslice form (if given a Byteslice form) with N forms/
       chars/bytes from left in Block/Quote/Byteslice form.
       If N is larger than Block/Quote/Byteslice form count,
       it is made equal to Block/Quote/Byteslice form count.
       Dies if N is negative.

      ```
      [ 1 2 3 ] 1 fromLeft* leaves: [ [ 1 ] ]
      [ 1 2 3 ] 2 fromLeft* leaves: [ [ 1 2 ] ]
      [ 1 2 3 ] 3 fromLeft* leaves: [ [ 1 2 3 ] ]
      [ 1 2 3 ] 100 fromLeft* leaves: [ [ 1 2 3 ] ]
      'hello' 3 fromLeft* leaves: 'hel'
      ```
      END
      ) do |_, stack|
        size = stack.drop.a(Decimal).posint
        form = stack.drop.a(Block | Quote | Byteslice)
        form.at(0, size.to_i - 1).onto(stack)
      end

      target.at("fromRight*", <<-END
      ( B/Q/Bf N -- Fb/Rq/Rbf ): leaves Elements block (if given
       a Block), Result quote (if given a Quote), or Result
       byteslice form (if given a Byteslice form) with N forms/
       chars/bytes from right in Block/Quote/Byteslice form.
       If N is larger than Block/Quote/Byteslice form count,
       it is made equal to Block/Quote/Byteslice form count.
       Dies if N is negative.

      ```
      [ 1 2 3 ] 1 fromRight* leaves: [ [ 3 ] ]
      [ 1 2 3 ] 2 fromRight* leaves: [ [ 2 3 ] ]
      [ 1 2 3 ] 3 fromRight* leaves: [ [ 1 2 3 ] ]
      [ 1 2 3 ] 100 fromRight* leaves: [ [ 1 2 3 ] ]
      ```
      END
      ) do |_, stack|
        size = stack.drop.a(Decimal).posint
        form = stack.drop.a(Block | Quote | Byteslice)
        form.at(form.count - size.to_i, form.count - 1).onto(stack)
      end

      target.at("+", "( A B -- S ): leaves the Sum of two decimals.") do |_, stack|
        b = stack.drop.a(Decimal)
        a = stack.drop.a(Decimal)
        stack.add(a + b)
      end

      target.at("-", "( A B -- D ): leaves the Difference of two decimals.") do |_, stack|
        b = stack.drop.a(Decimal)
        a = stack.drop.a(Decimal)
        stack.add(a - b)
      end

      target.at("*", "( A B -- P ): leaves the Product of two decimals.") do |_, stack|
        b = stack.drop.a(Decimal)
        a = stack.drop.a(Decimal)
        stack.add(a * b)
      end

      target.at("/", "( A B -- Q ): leaves the Quotient of two decimals.") do |_, stack|
        b = stack.drop.a(Decimal)
        a = stack.drop.a(Decimal)
        b.die("division by zero") if b.zero?
        stack.add(a / b)
      end

      target.at("mod", "( A B -- M ): leaves the Modulo of two decimals.") do |_, stack|
        b = stack.drop.a(Decimal)
        a = stack.drop.a(Decimal)
        b.die("modulo by zero") if b.zero?
        stack.add(a % b)
      end

      target.at("**", "( A B -- R ): raises A to the power B, leaves Result.") do |_, stack|
        b = stack.drop.a(Decimal)
        a = stack.drop.a(Decimal)
        stack.add(a ** b)
      end

      target.at("round", <<-END
      ( D -- Rd ): rounds Decimal towards the nearest integer,
       leaves the corresoinding Rounded decimal. If both neighboring
       integers are equidistant, rounds towards the even neighbor
       (Banker's rounding).

      ```
      1 round leaves: 1
      1.23 round leaves: 1

      1.5 round leaves: 2
      1.67 round leaves: 2

      2.5 round leaves: 2 "rounds towards the even neighbor"
      ```
      END
      ) do |_, stack|
        decimal = stack.drop.a(Decimal)
        decimal.round.onto(stack)
      end

      target.at("floor", <<-END
      ( D -- Rd ): rounds Decimal *down* towards the nearest integer,
       leaves the corresoinding Rounded decimal.

      ```
      1 floor leaves: 1
      1.23 floor leaves: 1

      1.5 floor leaves: 1
      1.67 floor leaves: 1

      2.5 floor leaves: 2

      -2.5 floor leaves: -3 "rounds down!"
      ```
      END
      ) do |_, stack|
        decimal = stack.drop.a(Decimal)
        decimal.floor.onto(stack)
      end

      target.at("ceil", <<-END
      ( D -- Rd ): rounds Decimal *up* towards the nearest integer,
       leaves the corresoinding Rounded decimal.

      ```
      1 ceil leaves: 1
      1.23 ceil leaves: 2

      1.5 ceil leaves: 2
      1.67 ceil leaves: 2

      2.5 ceil leaves: 3

      -2.5 ceil leaves: -2 "rounds up!"
      ```
      END
      ) do |_, stack|
        decimal = stack.drop.a(Decimal)
        decimal.ceil.onto(stack)
      end

      target.at("trunc", <<-END
      ( D -- Rd ): rounds Decimal towards zero, leaves the resulting
       Rounded decimal.

      ```
      1 trunc leaves: 1
      1.23 trunc leaves: 1
      1.5 trunc leaves: 1
      1.67 trunc leaves: 1
      2.5 trunc leaves: 2

      -2.3 trunc leaves:  -2
      ```
      END
      ) do |_, stack|
        decimal = stack.drop.a(Decimal)
        decimal.trunc.onto(stack)
      end

      target.at("sqrt", "( D -- R ): leaves the square Root of Decimal.") do |_, stack|
        decimal = stack.drop.a(Decimal)
        decimal.sqrt.onto(stack)
      end

      target.at("cos", <<-END
      ( Air -- Dc ): leaves Decimal cosine of Angle in radians.
      END
      ) do |_, stack|
        decimal = stack.drop.a(Decimal)
        decimal.rad_cos.onto(stack)
      end

      target.at("sin", <<-END
      ( Air -- Ds ): leaves Decimal sine of Angle in radians.
      END
      ) do |_, stack|
        decimal = stack.drop.a(Decimal)
        decimal.rad_sin.onto(stack)
      end

      target.at("rand", "( -- Rd ): leaves a Random decimal between 0 and 1.") do |_, stack|
        Decimal.new(rand).onto(stack)
      end

      target.at("sliceQuoteAt", <<-END
      ( Q Sp -- Pb Pa ): for the given Quote, leaves the Part
       before and Part after Slice point.

      ```
      'hello world' 2 sliceQuoteAt leaves: [ 'he' 'llo world' ]
      ```
      END
      ) do |_, stack|
        spt = stack.drop.a(Decimal)
        quote = stack.drop.a(Quote)
        qpre, qpost = quote.slice_at(spt.to_i)
        qpre.onto(stack)
        qpost.onto(stack)
      end

      target.at("count", <<-END
      ( B/Q/Bf -- N ): leaves N, the amount of elements/graphemes/
       bytes in Block/Quote/Byteslice form.
      END
      ) do |_, stack|
        form = stack.drop.a(Block | Quote | Byteslice)

        Decimal.new(form.count).onto(stack)
      end

      target.at("chr", <<-END
      ( Uc -- Q ): leaves a quote that consists of a single
       character with the given Unicode codepoint.
      END
      ) do |_, stack|
        ord = stack.drop.a(Decimal).posint.in(0..0xd7ff, 0xe000..0x10ffff)

        Quote.new(ord.chr).onto(stack)
      end

      target.at("ord", <<-END
      ( Q -- Uc ): leaves the Unicode codepoint for the first
       character in Quote. Dies if Quote is empty.
      END
      ) do |_, stack|
        quote = stack.drop.a(Quote)

        unless ord = quote.ord?
          quote.die("ord: quote must contain at least one character")
        end

        Decimal.new(ord).onto(stack)
      end

      target.at("lpad", <<-END
      ( Q Tl Pq -- Jq ): appends consecutive characters from Padding quote
       (the last one is repeated if no more follow) to the left of Quote,
       until Quote count becomes equal to Total length. Leaves the resulting
       Justified quote. If Quote count is greater than or equal to Total
       length, Quote is left unchanged as the Justified quote.

      ```
      'hello' 10 '-' lpad leaves: '-----hello'
      'hello' 10 ':-' lpad leaves: ':----hello'
      'hello' 7 'XYZABC' lpad leaves: 'XYhello'
      'hello' 9 'XYZABC' lpad leaves: 'XYZAhello'
      ```
      END
      ) do |_, stack|
        padder = stack.drop.a(Quote)
        total = stack.drop.a(Decimal).posint
        quote = stack.drop.a(Quote)
        quote.pad(total.to_i, padder, side: Quote::PadSide::Left).onto(stack)
      end

      target.at("rpad", <<-END
      ( Q Tl Pq -- Jq ): appends consecutive characters from Padding quote
       (the last one is repeated if no more follow) to the right of Quote,
       until Quote count becomes equal to Total length. Leaves the resulting
       Justified quote. If Quote count is greater than or equal to Total
       length, Quote is left unchanged as the Justified quote.

      ```
      'hello' 10 '-' rpad leaves: 'hello-----'
      'hello' 10 ' -' rpad leaves: 'hello ----'
      'hello' 7 'foobar' rpad leaves: 'hellofo'
      ```
      END
      ) do |_, stack|
        padder = stack.drop.a(Quote)
        total = stack.drop.a(Decimal).posint
        quote = stack.drop.a(Quote)
        quote.pad(total.to_i, padder, side: Quote::PadSide::Right).onto(stack)
      end

      target.at("fit", <<-END
      ( Q Tl Eq -- Fq ): if Quote is longer than Total length, truncates
       it so that it can fit Ellipsis quote, and stitches the truncated
       Quote with the Ellipsis quote, forming Fit quote which is then
       left on the stack.

      Essentially, Fit quote is guaranteed to be of Total length
      characters **or less!**.

      ```
      'hello' 10 '…' fit leaves: 'hello'
      'hello world' 10 '…' fit leaves: 'hello wor…'
      'hello world' 8 '' fit leaves: 'hello wo'
      'Lorem ipsum dolor sit amet' 10 '-' fit leaves: 'Lorem ipsu-'
      'Lorem ipsum dolor sit amet' 24 '… (hidden)' fit leaves: 'Lorem ipsum do… (hidden)'
      ```
      END
      ) do |_, stack|
        ellipsis = stack.drop.a(Quote)
        total = stack.drop.a(Decimal).posint
        quote = stack.drop.a(Quote)
        quote.fit(total.to_i, ellipsis).onto(stack)
      end

      target.at("|at", "( B -- N ): leaves N, the position of the cursor in Block.") do |_, stack|
        block = stack.drop.a(Block)
        cursor = Decimal.new(block.cursor)
        cursor.onto(stack)
      end

      target.at("|to", "( B N -- ): moves the cursor in Block to N.") do |_, stack|
        cursor = stack.drop.a(Decimal)
        block = stack.drop.a(Block)
        block.to(cursor.to_i)
      end

      target.at("<|", "( -- ): moves stack cursor once to the left.") do |_, stack|
        stack.to(stack.cursor - 1)
      end

      target.at("|>", "( -- ): moves stack cursor once to the left.") do |_, stack|
        stack.to(stack.cursor + 1)
      end

      target.at("|slice", <<-END
      ( B -- Lh Rh ): slices Block at cursor. Leaves Left half
       and Right half.
      END
      ) do |_, stack|
        block = stack.drop.a(Block)
        lhs, rhs = block.slice
        lhs.onto(stack)
        rhs.onto(stack)
      end

      target.at("cherry", <<-END
      ( [ ... E | ... ]B ~> [ ... | ... ]B -- E ): drops Block
       and Element before cursor in Block (and moves cursor back
       once), leaves Element.
      END
      ) do |_, stack|
        stack.drop.a(Block).drop.onto(stack)
      end

      target.at("shove", <<-END
      ( [ ... | ... ]B E ~> [ ... E | ... ]B -- ): adds Element
       before cursor in Block (and moves cursor forward once),
       drops both.
      END
      ) do |_, stack|
        stack.drop.onto(stack.drop.a(Block))
      end

      target.at("shove*", <<-END
      ( [ ...bl | ...br ]B [ ...el | ...er ]Eb ~> [ ...bl ...el | ...br ]B -- ): adds
       elements before cursor in Element block after the cursor in Block.

      ```
      [ 1 2 3 ] $: xs
      xs [ 4 5 6 ] shove*
      xs leaves: [ [ 1 2 3 4 5 6 "|" ] ]

      [ 1 | 2 3 ] $: ys
      ys [ 100 200 300 ] shove*
      ys leaves: [ 1 100 200 300 | 2 3 ]
      ```
      END
      ) do |_, stack|
        elems = stack.drop.a(Block)
        block = stack.drop.a(Block)
        block.paste(elems)
      end

      target.at("eject", <<-END
      ( [ ... | F ... ]B ~> [ ... | ... ]B -- F ): drops and
       leaves the Form after cursor in Block.
      END
      ) do |_, stack|
        block = stack.drop.a(Block)
        form = block.eject
        form.onto(stack)
      end

      target.at("inject", <<-END
      ( B F -- ): inserts Form to Block: adds Form to Block,
       and moves cursor back again.
      END
      ) do |_, stack|
        form = stack.drop
        block = stack.drop.a(Block)
        block.inject(form)
      end

      target.at("thru", <<-END
      ( [ ... | F ... ] -> [ ... F | ... ] -- F ): moves cursor
       after Form, and leaves Form. Dies if cursor is at the end.

      Note: prefer `thru` to `eject` because `eject` modifies
      the block, and that may cause a tape copy which uses up
      a bit of memory and resources. The difference would matter
      only in high load scenarios, though.

      Note: anything that *does not* `ahead inject` will be OK
      with `ahead thru`. And even if it does `ahead inject`,
      still, there are ways to overcome the problems from not
      `ahead eject`ing.
      END
      ) do |_, stack|
        block = stack.drop.a(Block)
        block.thru.onto(stack)
      end

      target.at("thruBlock", <<-END
      ( B -- Bf / [ Vf ] ): similar to `thru` for Block. If
       form after cursor is a Block form, it is left. If it is
       a Value form, then it is enclosed in a new block whose
       parent is Block.
      END
      ) do |_, stack|
        block = stack.drop.a(Block)
        form = block.thru
        if form.is_a?(Block)
          form.onto(stack)
        else
          child = Block.new(block)
          child.add(form)
          child.onto(stack)
        end
      end

      target.at("top", "( [ ... F | ... ]B -- F ): leaves the top Form in Block.") do |_, stack|
        block = stack.drop.a(Block)
        block.top.onto(stack)
      end

      target.at("mergeDicts", <<-END
      ( Rb Db -- ): copies entries from Donor block's dictionary
       to Recipient block's dictionary. Donor entries override
       same-named entries in Recipient. Donor entries starting
       with one or more underscores are not imported.

      ```
      [ ] $: a
      a #x 100 pushes
      a #_private 'Fool!' pushes
      [ ] $: b
      b #y 200 pushes

      a b 2echo
      "STDOUT: [ · ${x :: 100} ${_private :: 'Fool!'} ]⏎"
      "STDOUT: [ · ${y :: 200} ]⏎"

      b a mergeDicts
      b echo
      "STDOUT: [ · ${y :: 200} ${x :: 100} ]⏎"
      ```
      END
      ) do |_, stack|
        donor = stack.drop.a(Block)
        recpt = stack.drop.a(Block)
        recpt.import!(from: donor)
      end

      # FIXME!
      #
      # This is a stub before I can get to writing a sorting algo
      # in Novika. E.g. one of the drawbacks is that it doens't
      # support break and next (and it's impossible to support them
      # without writing a ton of unidiomatic shitcode). The latter
      # results in heaps of unelegant code, but ANYWAY ...

      target.at("sortUsing!", <<-END
      ( B Cb -- B ): leaves Block sorted inplace. Forms in Block
       are compared using Comparator block.

      Comparator block is opened with two forms on the stack; let's
      call them A and B. If Comparator block leaves a negative decimal
      (conventionally `-1`), then `A < B`. If Comparator block leaves
      `0`, then `A = B`. If Comparator block leaves a positive decimal
      (conventionally `1`), then `A > B`.

      Dies if Comparator block leaves any other (kind of) form.

      Ignores all forms but the topmost for Comparator block.


      ```
      [ 3 2 1 ] [ - ] sortUsing! leaves: [ 1 2 3 ]
      ```
      END
      ) do |_, stack|
        cmp = stack.drop.a(Block)
        block = stack.top.a(Block)
        block.sort_using! do |a, b|
          stack = Block.with(a, b)

          # Hacky hack, see the comment above.
          Engine.exhaust(Engine.current.capabilities, cmp, stack).top.a(Decimal).to_i
        end
      end

      target.at("getErrorDetails", <<-END
      ( Eo -- Dq ): leaves Details quote containing error details
       of an Error object.
      END
      ) do |_, stack|
        error = stack.drop.a(Error)
        Quote.new(error.details).onto(stack)
      end

      target.at("toQuote", "( F -- Qr ): leaves Quote representation of Form.") do |_, stack|
        stack.drop.to_quote.onto(stack)
      end

      target.at("toByteslice", "( Q -- B ): leaves immutable Byteslice for Quote.") do |_, stack|
        stack.drop.a(Quote).to_byteslice.onto(stack)
      end

      target.at("replaceAll", <<-END
      ( Sq Pq Q -- Rq ): replaces all instances of Pattern quote
       in Source quote with Quote. Leaves the Resulting quote.

      ```
      'hello' 'l' 'y' replaceAll leaves: 'heyyo'
      ```
      END
      ) do |_, stack|
        repl = stack.drop.a(Quote)
        pattern = stack.drop.a(Quote)
        quote = stack.drop.a(Quote)
        quote.replace_all(pattern, repl).onto(stack)
      end

      target.at("effect", <<-END
      ( F -- Eq ): leaves Effect quote for Form.

      If Form is not a block nor a builtin, it is simply converted
      to quote in the same way as `toQuote`.

      If Form is a block or a builtin, an attempt is made at
      extracting a stack effect expression from its comment.
      If the attempt fails, Form's description is left. If the
      attempt was successful, the extracted stack effect quote
      is added onto the stack as Effect quote.

      ```
      100 effect leaves: '100'
      true effect leaves: 'true'

      [] effect leaves: 'a block'
      [ "Hello World" ] effect leaves: 'a block'
      [ "( -- ) "] effect leaves: '( -- )'

      #+ here effect leaves: '( A B -- S )' "(yours may differ)"
      #map: here effect leaves: '( Lb B -- MLb )'
      ```
      END
      ) do |_, stack|
        Quote.new(stack.drop.effect).onto(stack)
      end

      target.at("die", <<-END
      ( D/Eo -- ): dies with Details quote/Error object.
      END
      ) do |engine, stack|
        form = stack.drop.a(Quote | Error)
        case form
        in Quote then raise engine.die(form.string)
        in Error then raise form
        end
      end

      target.at("stitch", "( Q1 Q2 -- Q3 ): quote concatenation.") do |_, stack|
        b = stack.drop.a(Quote)
        a = stack.drop.a(Quote)
        stack.add a.stitch(b)
      end

      target.at("reparent", <<-END
      ( C P -- C ): changes the parent of Child to Parent. Lookup
       cycles are allowed and handled gracefully.
      END
      ) do |_, stack|
        parent = stack.drop.a(Block)
        child = stack.top.a(Block)
        child.parent = parent
      end

      target.at("befriend", <<-END
      ( B F -- ): adds Friend to Block's friend list.

      Friends are asked for word entries after parents, grandparents
      etc. have failed to retrieve them. This recurses, e.g. friends
      ask their own friends and so on, until the entry is found. Lookup
      cycles are allowed and handled gracefully.

      ```
      [ 100 $: x this ] open $: a
      [ 200 $: y this ] open $: b
      a b befriend
      b a befriend
      a.x echo
      "STDOUT: 100⏎"

      a.y echo
      "STDOUT: 200⏎"

      b.x echo
      "STDOUT: 100⏎"

      b.y echo
      "STDOUT: 200⏎"

      a #x [ 'I\\'ve changed!' echo ] opens

      a.x
      "STDOUT: I've changed!⏎"
      b.x
      "STDOUT: I've changed!⏎"
      ```
      END
      ) do |_, stack|
        friend = stack.drop.a(Block)
        block = stack.drop.a(Block)
        block.befriend(friend)
      end

      target.at("unfriend", <<-END
      ( B F -- ): removes Friend from Block's friend list. Does
       nothing if Friend is not in the friend list. See `befriend`.

      ```
      [ 100 $: x this ] open $: a
      [ 200 $: y this ] open $: b
      a b befriend
      a.x echo
      "STDOUT: 100⏎"
      a.y echo
      "STDOUT: 200⏎"
      a b unfriend
      a.x echo
      "STDOUT: 100⏎"
      a.y echo
      "Sorry: no value form found for 'y'."
      ```
      END
      ) do |_, stack|
        friend = stack.drop.a(Block)
        source = stack.drop.a(Block)
        source.unfriend(friend)
      end

      target.at("friends", <<-END
      ( B -- Fl ): leaves Friend list of Block. See `befriend`.

      ```
      [ 100 $: x this ] open $: a
      [ 200 $: y this ] open $: b
      a b befriend
      a friends count echo
      "STDOUT: 1⏎"
      a friends first b same? echo
      "STDOUT: true⏎"
      a.y echo
      "STDOUT: 200⏎"
      a friends [ drop ] hydrate
      a friends count echo
      "STDOUT: 0⏎"
      a.y echo
      "Sorry: no value form found for 'y'."
      ```
      END
      ) do |_, stack|
        source = stack.drop.a(Block)
        source.friends.onto(stack)
      end

      target.at("slurp", <<-END
      ( B Q -- B ): parses Quote and adds all forms from Quote
       to Block.
      END
      ) do |_, stack|
        source = stack.drop.a(Quote)
        block = stack.top.a(Block)
        block.slurp(source.string)
      end

      target.at("orphan", "( -- O ): Leaves an Orphan (a parent-less block).") do |_, stack|
        Block.new.onto(stack)
      end

      target.at("orphan?", "( B -- true/false ): leaves whether Block is an orphan") do |_, stack|
        Boolean[!stack.drop.a(Block).parent?].onto(stack)
      end

      target.at("toOrphan", <<-END
      ( B -- B ): makes Block an orphan (destroys the link with
       its parent).

      ```
      0 $: x
      [ ] $: b
      b . x echo
      "STDOUT: 0⏎"

      b toOrphan leaves: [ [ ] ]
      . x
      "Sorry: no value form found for 'x'""
      ```
      END
      ) do |_, stack|
        stack.top.a(Block).parent = nil
      end

      target.at("toTape", <<-END
      ( B -- Tb ): leaves Tape block for Block, i.e., the tape part
       of Block. Useful for e.g. comparing two blocks only for tape
       content, when Block may have dictionary entries.

      Lookup hierarchy is destroyed: Tape block is an orphan.

      ```
      [ 1 2 3 ] $: a
      a #x 0 pushes
      a (a toTape) 2echo
      "STDOUT: [ 1 2 3 · ${x :: 0} ]⏎"
      "STDOUT: [ 1 2 3 ]⏎"
      ```
      END
      ) do |_, stack|
        block = stack.drop.a(Block)
        block.to_tape_block.onto(stack)
      end

      target.at("toDict", <<-END
      ( B -- Db ): leaves Dictionary block for Block, i.e., the dictionary
       part of Block. Useful for e.g. comparing two blocks only for dictionary
       content in case tape contents differ.

      Lookup hierarchy is destroyed: Dictionary block is an orphan.

      ```
      [ ${ x y } this ] @: createPoint

      10 20 createPoint $: a
      10 20 createPoint $: b

      a b = leaves: false

      "And not for the reason you might think of. Their TAPES are not
       equal; `a` and `b` are not only objects, they are also pieces
       of code that led to each one's creation (sort of)."
      a toQuote leaves: '[ ${ x y } this · ${x :: 10} ${y :: 20} ]'
      b toQuote leaves: '[ ${ x y } this · ${x :: 10} ${y :: 20} ]'

      "Let's strip the code using toDict:"
      a toDict leaves: '[ · ${x :: 10} ${y :: 20} ]'
      b toDict leaves: '[ · ${x :: 10} ${y :: 20} ]'
             = leaves: true "< now they're equal"
      ```
      END
      ) do |_, stack|
        block = stack.drop.a(Block)
        block.to_dict_block.onto(stack)
      end

      target.at("desc", <<-END
      ( F -- Dq ): leaves the Description quote of the given Form.

      ```
      100 desc leaves: 'decimal number 100'
      'foobar' desc leaves: 'quote \\\\'foobar\\\\''
      [ 1 2 3 ] desc leaves: 'a block'
      [ "I am a block" 1 2 3 ] desc leaves: 'I am a block'
      true desc leaves: 'boolean true'
      ```
      END
      ) do |_, stack|
        quote = Quote.new(stack.drop.desc)
        quote.onto(stack)
      end

      target.at("typedesc", <<-END
      ( F -- Dq ): leaves the type Description quote of the
       given Form.

      ```
      100 typedesc leaves: 'decimal'
      'foobar' typedesc leaves: 'quote'
      [ 1 2 3 ] typedesc leaves: 'block'
      [ "I am a block" 1 2 3 ] typedesc leaves: 'block'
      true typedesc leaves: 'boolean'
      ```
      END
      ) do |_, stack|
        quote = Quote.new(stack.drop.class.typedesc)
        quote.onto(stack)
      end
    end
  end
end
