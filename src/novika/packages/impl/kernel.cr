{% if flag?(:novika_readline) %} require "readline" {% end %}

module Novika::Packages::Impl
  class Kernel
    include Package

    def self.id : String
      "kernel"
    end

    def self.purpose : String
      "exposes the native code primitives, such as 'hydrate' and 'new'"
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

      target.at("conts", "( -- Cs ): Pushes the Continuations block.") do |engine|
        engine.conts.push(engine)
      end

      target.at("newContinuation", "( S B -- C ): creates a Continuation from a Stack and a Block.") do |engine|
        block = engine.stack.drop.assert(engine, Block)
        stack = engine.stack.drop.assert(engine, Block)
        Engine.cont(block, stack).push(engine)
      end

      target.at("dup", "( F -- F F ): duplicates the Form before cursor.", &.stack.dupe)
      target.at("drop", "( F -- ): drops the Form before cursor.", &.stack.drop)
      target.at("swap", "( A B -- B A ): swaps two Forms before cursor.", &.stack.swap)
      target.at("hydrate", "( S F -- ): opens Form with Stack set as the active stack.") do |engine|
        form = engine.stack.drop
        stack = engine.stack.drop.assert(engine, Block)
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

      target.at("word?", "( F -- true/false ): leaves whether Form is a word.") do |engine|
        Boolean[engine.stack.drop.is_a?(Word)].push(engine)
      end

      target.at("asWord", <<-END
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
            form.die("asWord: quote argument is empty")
          elsif string.each_char.any?(&.whitespace?)
            form.die("asWord: quote argument contains whitespace")
          end
          Word.new(form.string).push(engine)
        else
          form.die("asWord: quote must be one of: word, quote, quoted word")
        end
      end

      target.at("quotedWord?", "( F -- true/false ): leaves whether Form is a quoted word.") do |engine|
        Boolean[engine.stack.drop.is_a?(QuotedWord)].push(engine)
      end

      target.at("decimal?", "( F -- true/false ): leaves whether Form is a decimal.") do |engine|
        Boolean[engine.stack.drop.is_a?(Decimal)].push(engine)
      end

      target.at("quote?", "( F -- true/false ): leaves whether Form is a quote.") do |engine|
        Boolean[engine.stack.drop.is_a?(Quote)].push(engine)
      end

      target.at("boolean?", "( F -- true/false ): leaves whether Form is a boolean.") do |engine|
        Boolean[engine.stack.drop.is_a?(Boolean)].push(engine)
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

      target.at("fromLeft", "( B I -- E ): leaves Index-th Element in Block from the left.") do |engine|
        index = engine.stack.drop.assert(engine, Decimal)
        block = engine.stack.drop.assert(engine, Block)
        block.at(index.to_i).push(engine)
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

      target.at("charCount", "( Q -- N ): leaves N, the amount of characters in Quote") do |engine|
        quote = engine.stack.drop.assert(engine, Quote)
        Decimal.new(quote.string.size).push(engine)
      end

      target.at("sliceQuoteAt", <<-END
      ( Q Spt -- Qpre Qpost ): given a Quote, slices it before (Qpre) and
       after and including (Qpost) Slice point.
      END
      ) do |engine|
        spt = engine.stack.drop.assert(engine, Decimal)
        spti = spt.to_i

        quote = engine.stack.drop.assert(engine, Quote)
        s = quote.string

        if s.size.zero?
          spt.die("quote is empty, cannot sliceQuoteAt")
        elsif spti.negative?
          spt.die("cannot sliceQuoteAt negative slicepoint")
        elsif spti > s.size
          spt.die("cannot sliceQuoteAt slicepoint exceeding quote charCount")
        end

        # Handle a bunch of quickies.
        if spti.zero?
          Quote.new("").push(engine)
          quote.push(engine)
        elsif spti == s.size
          quote.push(engine)
          Quote.new("").push(engine)
        else
          Quote.new(quote.string[...spti]).push(engine)
          Quote.new(quote.string[spti..]).push(engine)
        end
      end

      target.at("count", "( B -- N ): leaves N, the amount of elements in Block.") do |engine|
        block = engine.stack.drop.assert(engine, Block)
        count = Decimal.new(block.count)
        count.push(engine)
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

      target.at("top", "( [ ... F | ... ]B -- F ): leaves the top Form in Block.") do |engine|
        block = engine.stack.drop.assert(engine, Block)
        block.top.push(engine)
      end

      target.at("mergeTables") do |engine|
        donor = engine.stack.drop.assert(engine, Block)
        recpt = engine.stack.drop.assert(engine, Block)
        recpt.import!(from: donor)
      end

      target.at("enquote", "( F -- Qr ): leaves Quote representation of Form.") do |engine|
        engine.stack.drop.enquote(engine).push(engine)
      end

      target.at("die", "( D -- ): dies with Details quote.") do |engine|
        raise Died.new(engine.stack.drop.assert(engine, Quote).string)
      end

      target.at("stitch", "( Q1 Q2 -- Q3 ): quote concatenation.") do |engine|
        b = engine.stack.drop.assert(engine, Quote)
        a = engine.stack.drop.assert(engine, Quote)
        engine.stack.add(a + b)
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
