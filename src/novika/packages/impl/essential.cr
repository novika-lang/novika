{% if flag?(:novika_readline) %} require "readline" {% end %}

module Novika::Packages::Impl
  class Essential
    include Package

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

      target.at("prototype", "( B -- P ): leaves the Prototype of Block.") do |engine|
        block = engine.stack.drop.assert(engine, Block)
        block.prototype.push(engine)
      end

      target.at("parent", "( B -- P ): leaves the Parent of Block.") do |engine|
        block = engine.stack.drop.assert(engine, Block)
        block.parent.push(engine)
      end

      target.at("conts", "( -- Cs ): pushes the Continuations block.") do |engine|
        engine.conts.push(engine)
      end

      target.at("cont", "( -- Cs ): pushes the Continuation block.") do |engine|
        engine.cont.push(engine)
      end

      target.at("newContinuation", "( S B -- C ): creates a Continuation from a Stack and a Block.") do |engine|
        block = engine.stack.drop.assert(engine, Block)
        stack = engine.stack.drop.assert(engine, Block)
        Engine.cont(block, stack).push(engine)
      end

      target.at("getContBlock", <<-END
      ( C -- cB ): leaves the continuation Block of a Continuation.
      END
      ) do |engine|
        cont = engine.stack.drop.assert(engine, Block)
        cont.at(Engine::C_BLOCK_AT).push(engine)
      end

      target.at("getContStack", <<-END
      ( C -- cS ): leaves the continuation Stack of a Continuation.
      END
      ) do |engine|
        cont = engine.stack.drop.assert(engine, Block)
        cont.at(Engine::C_STACK_AT).push(engine)
      end

      target.at("this", <<-END
      ( -- B ): pushes a reflection of the block it's opened in.

      >>> [ this ] open
      === [ this ]+ (instance of `[ this ]`)
      >>> prototype
      === [ this ] (I told you!)
      END
      ) do |engine|
        engine.block.push(engine)
      end

      target.at("stack", <<-END
      ( -- S ): pushes the Stack it's opened in.

      >>> stack
      === [a reflection]
      >>> 'foo' <<
      === [a reflection] 'foo'
      END
      ) do |engine|
        engine.stack.push(engine)
      end

      target.at("ahead", <<-END
      ( -- B ): leaves the block that will be executed after
       `this` finishes.

      >>> 100 [ ahead 1 inject ] open +
      === 101 (i.e. 100 1 +)
      END
      ) do |engine|
        cont = engine.conts.at(engine.conts.count - 2)
        cont = cont.as?(Block) || cont.die("malformed continuation")
        ahead = cont.at(Engine::C_BLOCK_AT)
        ahead.push(engine)
      end

      target.at("dup", "( F -- F F ): duplicates the Form before cursor.", &.stack.dupe)
      target.at("drop", "( F -- ): drops the Form before cursor.", &.stack.drop)
      target.at("swap", "( A B -- B A ): swaps two Forms before cursor.", &.stack.swap)
      target.at("hydrate", <<-END
      ( S F -- ): opens (evaluates) Form with Stack set as the
       active stack. If Form is not a block, it is added to
       Stack (equivalent to `<<`), If Form is a block, its
       instance is opened. To open a block without creating
       an instance of it (unsafe), use `hydrate!`.
      END
      ) do |engine|
        form = engine.stack.drop
        stack = engine.stack.drop.assert(engine, Block)
        engine.schedule(form, stack)
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
      ) do |engine|
        form = engine.stack.drop
        stack = engine.stack.drop.assert(engine, Block)
        engine.schedule!(form, stack)
      end

      target.at("open", <<-END
      ( F -- F' ): opens Form in the active stack. Equivalent
       to `stack F hydrate`.

      >>> 100 open
      === 100

      >>> 1 [ 2 + ] open
      === 3
      END
      ) do |engine|
        form = (stack = engine.stack).drop
        engine.schedule(form, stack)
      end

      target.at("new", "( B -- I ): leaves an Instance of a Block.") do |engine|
        block = engine.stack.drop.assert(engine, Block)
        block.instance.push(engine)
      end

      target.at("sel", <<-END
    ( D A B -- A/B ): selects A (Determiner is truthy) or B
     (Determiner is falsey)
    END
      ) do |engine|
        b = engine.stack.drop
        a = engine.stack.drop
        det = engine.stack.drop
        det.sel(a, b).push(engine)
      end

      target.at("<", "( A B -- S ): leaves whether one decimal is smaller than other.") do |engine|
        b = engine.stack.drop.assert(engine, Decimal)
        a = engine.stack.drop.assert(engine, Decimal)
        Boolean[a < b].push(engine)
      end

      target.at("same?", <<-END
    ( F1 F2 -- true/false ): leaves whether two Forms are the
     same (by reference for block, by value  for any other form).
    END
      ) do |engine|
        b = engine.stack.drop
        a = engine.stack.drop
        Boolean.same?(a, b).push(engine)
      end

      target.at("=", <<-END
    ( F1 F2 -- true/false ): leaves whether two Forms are equal
     (they may or may not be same forms, i.e., those for which
     `same?` would leave true).
    END
      ) do |engine|
        b = engine.stack.drop
        a = engine.stack.drop
        Boolean[a == b].push(engine)
      end

      target.at("uppercase?", <<-END
      ( Q -- true/false ): leaves whether Quote consists of only
       uppercase characters. If Quote is empty, leaves false.
      END
      ) do |engine|
        quote = engine.stack.drop.assert(engine, Quote)
        s = quote.string
        Boolean[!s.empty? && ((s.size == 1 && s[0].uppercase?) || s.each_char.all?(&.uppercase?))].push(engine)
      end

      target.at("toUppercase", <<-END
      (Q -- Uq): converts lowercase character(s) in Quote
       to Uppercase. If Quote is empty, leaves empty quote.
       Behaves a bit like `uppercase?`.
      END
      ) do |engine|
        quote = engine.stack.drop.assert(engine, Quote)
        Quote.new(quote.string.upcase).push(engine)
      end

      target.at("block?", "( F -- true/false ): leaves whether Form is a block.") do |engine|
        Boolean[engine.stack.drop.is_a?(Block)].push(engine)
      end

      target.at("asBlock", <<-END
      ( F -- B ): asserts that Form is a Block, dies otherwise.

      >>> 100 asBlock
      [dies]
      >>> 'foo' asBlock
      [dies]
      >>> #foo asBlock
      [dies]
      >>> ##foo asBlock
      [dies]
      >>> [] asBlock
      === [] (the same block)
      >>> true asBlock
      [dies]
      END
      ) do |engine|
        engine.stack.top.assert(engine, Block)
      end

      target.at("word?", "( F -- true/false ): leaves whether Form is a word.") do |engine|
        Boolean[engine.stack.drop.is_a?(Word)].push(engine)
      end

      target.at("toWord", <<-END
      ( F -- W ): converts Form into Word.
        1. If Form is a word, behaves as noop
        2. If Form is a quote, dies only if quote contains (Unicode) whitespace characters
         or is itself empty.
        3. If Form is a quoted word, peels off **all** quoting
      END
      ) do |engine|
        form = engine.stack.drop
        case form
        when Word       then form.push(engine)
        when QuotedWord then form.to_word.push(engine)
        when Quote
          string = form.string
          if string.empty?
            form.die("toWord: quote argument is empty")
          elsif string.each_char.any?(&.whitespace?)
            form.die("toWord: quote argument contains whitespace")
          end
          Word.new(form.string).push(engine)
        else
          form.die("toWord: quote must be one of: word, quote, quoted word")
        end
      end

      target.at("asWord", <<-END
      ( F -- W ): asserts that Form is a Word, dies otherwise.

      Tries to invoke *asWord while Form or result thereof is
      a block.

      >>> 100 asWord
      [dies]
      >>> 'foo' asWord
      [dies]
      >>> #foo asWord
      === foo
      >>> ##foo asWord
      [dies]
      >>> [] asWord
      [dies]
      >>> true asWord
      [dies]
      >>> [ $: x x $: *asWord this ] @: a
      >>> 100 a asWord
      [dies]
      >>> 'foo' a asWord
      [dies]
      >>> #foo a asWord
      === instance of a
      >>> ##foo asWord
      [dies]
      >>> [] a asWord
      [dies]
      >>> true a asWord
      [dies]
      END
      ) do |engine|
        engine.stack.top.assert(engine, Word)
      end

      target.at("quotedWord?", "( F -- true/false ): leaves whether Form is a quoted word.") do |engine|
        Boolean[engine.stack.drop.is_a?(QuotedWord)].push(engine)
      end

      target.at("asQuotedWord", <<-END
      ( F -- Qw ): asserts that Form is a Quoted word, dies otherwise.

      Tries to invoke *asQuotedWord while Form or result thereof is
      a block implementing *asQuotedWord.

      >>> 100 asQuotedWord
      [dies]
      >>> 'foo' asQuotedWord
      [dies]
      >>> #foo asQuotedWord
      [dies]
      >>> ##foo asQuotedWord
      === #foo
      >>> [] asQuotedWord
      [dies]
      >>> true asQuotedWord
      [dies]
      >>> [ $: x x $: *asQuotedWord this ] @: a
      >>> 100 a asQuotedWord
      [dies]
      >>> 'foo' a asQuotedWord
      [dies]
      >>> #foo a asQuotedWord
      [dies]
      >>> ##foo a asQuotedWord
      === instance of a
      >>> [] a asQuotedWord
      [dies]
      >>> true a asQuotedWord
      [dies]
      END
      ) do |engine|
        engine.stack.top.assert(engine, QuotedWord)
      end

      target.at("decimal?", "( F -- true/false ): leaves whether Form is a decimal.") do |engine|
        Boolean[engine.stack.drop.is_a?(Decimal)].push(engine)
      end

      target.at("asDecimal", <<-END
      ( F -- D ): asserts that Form is a Decimal, dies otherwise.

      Tries to invoke *asDecimal while Form or result thereof is
      a block implementing *asDecimal.

      >>> 100 asDecimal
      === 100
      >>> 'foo' asDecimal
      [dies]
      >>> #foo asDecimal
      [dies]
      >>> ##foo asDecimal
      [dies]
      >>> [] asDecimal
      [dies]
      >>> true asDecimal
      [dies]
      >>> [ $: x x $: *asDecimal this ] @: a
      >>> 100 a asDecimal
      === instance of a
      >>> 'foo' a asDecimal
      [dies]
      >>> #foo a asDecimal
      [dies]
      >>> ##foo a asDecimal
      [dies]
      >>> [] a asDecimal
      [dies]
      >>> true a asDecimal
      [dies]
      END
      ) do |engine|
        engine.stack.top.assert(engine, Decimal)
      end

      target.at("quote?", "( F -- true/false ): leaves whether Form is a quote.") do |engine|
        Boolean[engine.stack.drop.is_a?(Quote)].push(engine)
      end

      target.at("asQuote", <<-END
      ( F -- Q ): asserts that Form is a Quote, dies otherwise.

      Tries to invoke *asQuote while Form or result thereof is
      a block implementing *asQuote.

      >>> 100 asQuote
      [dies]
      >>> 'foo' asQuote
      === 'foo'
      >>> #foo asQuote
      [dies]
      >>> ##foo asQuote
      [dies]
      >>> [] asQuote
      [dies]
      >>> true asQuote
      [dies]
      >>> [ $: x x $: *asQuote this ] @: a
      >>> 100 a asQuote
      [dies]
      >>> 'foo' a asQuote
      === instance of a
      >>> #foo a asQuote
      [dies]
      >>> ##foo a asQuote
      [dies]
      >>> [] a asQuote
      [dies]
      >>> true a asQuote
      [dies]
      END
      ) do |engine|
        engine.stack.top.assert(engine, Quote)
      end

      target.at("boolean?", "( F -- true/false ): leaves whether Form is a boolean.") do |engine|
        Boolean[engine.stack.drop.is_a?(Boolean)].push(engine)
      end

      target.at("asBoolean", <<-END
      ( F -- B ): asserts that Form is a Boolean, dies otherwise.

      Tries to invoke *asBoolean while Form or result thereof is
      a block implementing *asBoolean.

      >>> 100 asBoolean
      [dies]
      >>> 'foo' asBoolean
      [dies]
      >>> #foo asBoolean
      [dies]
      >>> ##foo asBoolean
      [dies]
      >>> [] asBoolean
      [dies]
      >>> true asBoolean
      === true
      >>> [ $: x x $: *asBoolean this ] @: a
      >>> 100 a asBoolean
      [dies]
      >>> 'foo' a asBoolean
      [dies]
      >>> #foo a asBoolean
      [dies]
      >>> ##foo a asBoolean
      [dies]
      >>> [] a asBoolean
      [dies]
      >>> true a asBoolean
      === instance of a
      END
      ) do |engine|
        engine.stack.top.assert(engine, Boolean)
      end

      target.at("pushes", <<-END
    ( B N F -- ): creates a definition for Name in Block that
     pushes Form when resolved there.
    END
      ) do |engine|
        form = engine.stack.drop
        name = engine.stack.drop
        block = engine.stack.drop.assert(engine, Block)
        block.at name, Entry.new(form)
      end

      target.at("opens", <<-END
    ( B N F -- ): creates a definition for Name in Block that
     opens Form when resolved there.
    END
      ) do |engine|
        form = engine.stack.drop
        name = engine.stack.drop
        block = engine.stack.drop.assert(engine, Block)
        block.at name, OpenEntry.new(form)
      end

      target.at("submit", <<-END
    ( B N F -- ): changes the value form of an existing definition
     of Name in Block to Form, but keeps its resolution action
     (open/push).
    END
      ) do |engine|
        form = engine.stack.drop
        name = engine.stack.drop
        block = engine.stack.drop.assert(engine, Block)
        unless entry = block.at?(name)
          name.die("cannot #submit forms to an entry that does not exist")
        end
        entry.submit(form)
      end

      target.at("entry:exists?", <<-END
    ( T N -- true/false ): leaves whether Table can fetch
     value for Name.
    END
      ) do |engine|
        name = engine.stack.drop
        block = engine.stack.drop.assert(engine, Block)
        Boolean[block.has?(name)].push(engine)
      end

      target.at("entry:fetch", "( B N -- F ): leaves the value Form under Name in Block's table.") do |engine|
        name = engine.stack.drop
        block = engine.stack.drop.assert(engine, Block)
        block.at(name).push(engine)
      end

      target.at("entry:isOpenEntry?", <<-END
    ( B N -- true/false ): leaves whether an entry called Name
     in Block is an open entry.
    END
      ) do |engine|
        name = engine.stack.drop
        block = engine.stack.drop.assert(engine, Block)
        Boolean[block.at(name).is_a?(OpenEntry)].push(engine)
      end

      target.at("shallowCopy", <<-END
    ( B -- C ): makes a shallow copy of Block's tape, and
     leaves a Copy block with the tape copy set as Copy's tape.
    END
      ) do |engine|
        engine.stack.drop.assert(engine, Block).shallow.push(engine)
      end

      target.at("attach", "( O B -- ): replaces the tape of Block with Other's tape.") do |engine|
        block = engine.stack.drop.assert(engine, Block)
        other = engine.stack.drop.assert(engine, Block)
        block.attach(other)
      end

      target.at("fromLeft", <<-END
      ( B/Q I -- E/G ): leaves Index-th Element (Grapheme) in
       Block (Quote) from the left.
      END
      ) do |engine|
        index = engine.stack.drop.assert(engine, Decimal)
        form = engine.stack.drop

        case form
        when Block, Quote
          form.at(index.to_i).push(engine)
        else
          form.die("'fromLeft' expects block or quote, got: #{form}")
        end
      end

      target.at("+", "( A B -- S ): leaves the Sum of two decimals.") do |engine|
        b = engine.stack.drop.assert(engine, Decimal)
        a = engine.stack.drop.assert(engine, Decimal)
        engine.stack.add(a + b)
      end

      target.at("-", "( A B -- D ): leaves the Difference of two decimals.") do |engine|
        b = engine.stack.drop.assert(engine, Decimal)
        a = engine.stack.drop.assert(engine, Decimal)
        engine.stack.add(a - b)
      end

      target.at("*", "( A B -- P ): leaves the Product of two decimals.") do |engine|
        b = engine.stack.drop.assert(engine, Decimal)
        a = engine.stack.drop.assert(engine, Decimal)
        engine.stack.add(a * b)
      end

      target.at("/", "( A B -- Q ): leaves the Quotient of two decimals.") do |engine|
        b = engine.stack.drop.assert(engine, Decimal)
        a = engine.stack.drop.assert(engine, Decimal)
        b.die("division by zero") if b.zero?
        engine.stack.add(a / b)
      end

      target.at("rem", "( A B -- R ): leaves the Remainder of two decimals.") do |engine|
        b = engine.stack.drop.assert(engine, Decimal)
        a = engine.stack.drop.assert(engine, Decimal)
        b.die("division by zero") if b.zero?
        engine.stack.add(a % b)
      end

      target.at("round", "( D -- Dr ): leaves round Decimal.") do |engine|
        decimal = engine.stack.drop.assert(engine, Decimal)
        decimal.round.push(engine)
      end

      target.at("trunc", "( D -- Dt ): leaves truncated Decimal.") do |engine|
        decimal = engine.stack.drop.assert(engine, Decimal)
        decimal.trunc.push(engine)
      end

      target.at("rand", "( -- Rd ): random decimal between 0 and 1.") do |engine|
        Decimal.new(rand).push(engine)
      end

      target.at("sliceQuoteAt", <<-END
      ( Q Spt -- Qpre Qpost ): given a Quote, slices it before (Qpre) and
       after and including (Qpost) Slice point.
      END
      ) do |engine|
        spt = engine.stack.drop.assert(engine, Decimal)
        quote = engine.stack.drop.assert(engine, Quote)
        qpre, qpost = quote.slice_at(spt.to_i)
        qpre.push(engine)
        qpost.push(engine)
      end

      target.at("count", <<-END
      ( B/Q -- N ): leaves N, the amount of elements (graphemes)
       in Block (Quote).
      END
      ) do |engine|
        form = engine.stack.drop
        case form
        when Block, Quote
          Decimal.new(form.count).push(engine)
        else
          form.die("can 'count' blocks and quotes only, got: #{form}")
        end
      end

      target.at("|at", "( B -- N ): leaves N, the position of the cursor in Block.") do |engine|
        block = engine.stack.drop.assert(engine, Block)
        cursor = Decimal.new(block.cursor)
        cursor.push(engine)
      end

      target.at("|to", "( B N -- ): moves the cursor in Block to N.") do |engine|
        cursor = engine.stack.drop.assert(engine, Decimal)
        block = engine.stack.drop.assert(engine, Block)
        block.to(cursor.to_i)
      end

      target.at("<|", "( -- ): moves stack cursor once to the left.") do |engine|
        stack = engine.stack
        stack.to(stack.cursor - 1)
      end

      target.at("|>", "( -- ): moves stack cursor once to the left.") do |engine|
        stack = engine.stack
        stack.to(stack.cursor + 1)
      end

      target.at("|slice", "( B -- Lh Rh ): slices Block at cursor, leaves Left, Right halves.") do |engine|
        block = engine.stack.drop.assert(engine, Block)
        lhs, rhs = block.slice
        lhs.push(engine)
        rhs.push(engine)
      end

      target.at("cherry", <<-END
    ( [ ... E | ... ]B -- [ ... | ... ]B -- E ): drops Block
     and Element before cursor in Block (and moves cursor back
     once), leaves Element.
    END
      ) do |engine|
        engine.stack.drop.assert(engine, Block).drop.push(engine)
      end

      target.at("shove", <<-END
    ( [ ... | ... ]B E -- [ ... E | ... ]B -- ): adds Element
     before cursor in Block (and moves cursor forward once),
     drops both.
    END
      ) do |engine|
        engine.stack.drop.push(engine.stack.drop.assert(engine, Block))
      end

      target.at("eject", <<-END
      ( [ ... | F ... ]B -- [ ... | ... ]B -- F ): drops and
       leaves the Form after cursor in Block.
      END
      ) do |engine|
        block = engine.stack.drop.assert(engine, Block)
        form = block.eject
        form.push(engine)
      end

      target.at("inject", <<-END
      ( B F -- ): inserts Form to Block: adds Form to Block,
       and moves cursor back again.
      END
      ) do |engine|
        form = engine.stack.drop
        block = engine.stack.drop.assert(engine, Block)
        block.inject(form)
      end

      target.at("thru", <<-END
      ( [ ... | F ... ] -- [ ... F | ... ] -- F ): moves cursor
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
      ) do |engine|
        block = engine.stack.drop.assert(engine, Block)
        block.thru.push(engine)
      end

      target.at("top", "( [ ... F | ... ]B -- F ): leaves the top Form in Block.") do |engine|
        block = engine.stack.drop.assert(engine, Block)
        block.top.push(engine)
      end

      target.at("mergeTables") do |engine|
        donor = engine.stack.drop.assert(engine, Block)
        recpt = engine.stack.drop.assert(engine, Block)
        recpt.import!(from: donor)
      end

      target.at("getErrorDetails", <<-END
      ( Eo -- Dq ): leaves Details quote containing error details
       of an Error object.
      END
      ) do |engine|
        error = engine.stack.drop.assert(engine, Died)
        Quote.new(error.details).push(engine)
      end

      target.at("toQuote", "( F -- Qr ): leaves Quote representation of Form.") do |engine|
        engine.stack.drop.to_quote(engine).push(engine)
      end

      target.at("die", "( D -- ): dies with Details quote.") do |engine|
        raise Died.new(engine.stack.drop.assert(engine, Quote).string)
      end

      target.at("stitch", "( Q1 Q2 -- Q3 ): quote concatenation.") do |engine|
        b = engine.stack.drop.assert(engine, Quote)
        a = engine.stack.drop.assert(engine, Quote)
        engine.stack.add a.stitch(b)
      end

      target.at("ls", "( B -- Nb ): gathers all table entry names into Name block.") do |engine|
        block = engine.stack.drop.assert(engine, Block)
        result = Block.new
        block.ls.each do |form|
          result.add(form)
        end
        result.push(engine)
      end

      target.at("reparent", <<-END
    ( C P -- C ): changes the parent of Child to Parent. Checks
     for cycles which can hang the interpreter, therefore is
     O(N) where N is the amount of Parent's ancestors.
    END
      ) do |engine|
        parent = engine.stack.drop.assert(engine, Block)
        child = engine.stack.top.assert(engine, Block)

        # TODO: this seems to be too forgiving. Lookup cycles
        # are pretty dangerous.
        current = parent
        while current
          if current.same?(child)
            current.die("this reparent introduces a cycle")
          else
            current = current.parent?
          end
        end

        child.parent = parent
      end

      target.at("slurp", <<-END
    ( B Q -- B ): parses Quote and adds all forms from Quote
     to Block.
    END
      ) do |engine|
        source = engine.stack.drop.assert(engine, Quote)
        block = engine.stack.top.assert(engine, Block)
        block.slurp(source.string)
      end

      target.at("orphan", "( -- O ): Leaves an Orphan (a parent-less block).") do |engine|
        Block.new.push(engine)
      end

      target.at("orphan?", "( B -- true/false ): leaves whether Block is an orphan") do |engine|
        Boolean[!engine.stack.drop.assert(engine, Block).parent?].push(engine)
      end

      target.at("desc", "( F -- Hq ): leaves the description of Form.") do |engine|
        quote = Quote.new(engine.stack.drop.desc)
        quote.push(engine)
      end
    end
  end
end
