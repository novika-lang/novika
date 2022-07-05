require "readline"

module Novika::Packages
  class Kernel
    include Package

    def self.id
      "primitives"
    end

    # Populates *target* with Novika primitives.
    def inject(into target)
      target.at(Word.new("true"), True.new)
      target.at(Word.new("false"), False.new)

      target.at("prototype", "( B -- P ): leaves the Prototype of Block.") do |world|
        block = world.stack.drop.assert(world, Block)
        block.prototype.push(world)
      end

      target.at("parent", "( B -- P ): leaves the Parent of Block.") do |world|
        block = world.stack.drop.assert(world, Block)
        block.parent.push(world)
      end

      target.at("conts", "( -- Cs ): Pushes the Continuations block.") do |world|
        world.conts.push(world)
      end

      target.at("newContinuation", "( S B -- C ): creates a Continuation from a Stack and a Block.") do |world|
        block = world.stack.drop.assert(world, Block)
        stack = world.stack.drop.assert(world, Block)
        World.cont(block, stack).push(world)
      end

      target.at("this", "( -- B ): pushes the current continuation Block.") do |world|
        world.block.push(world)
      end

      target.at("stack", "( -- S ): pushes the active Stack (stack of the CC).") do |world|
        world.stack.push(world)
      end

      target.at("+", "( A B -- S ): leaves the Sum of two decimals.") do |world|
        b = world.stack.drop.assert(world, Decimal)
        a = world.stack.drop.assert(world, Decimal)
        world.stack.add(a + b)
      end

      target.at("-", "( A B -- D ): leaves the Difference of two decimals.") do |world|
        b = world.stack.drop.assert(world, Decimal)
        a = world.stack.drop.assert(world, Decimal)
        world.stack.add(a - b)
      end

      target.at("*", "( A B -- P ): leaves the Product of two decimals.") do |world|
        b = world.stack.drop.assert(world, Decimal)
        a = world.stack.drop.assert(world, Decimal)
        world.stack.add(a * b)
      end

      target.at("/", "( A B -- Q ): leaves the Quotient of two decimals.") do |world|
        b = world.stack.drop.assert(world, Decimal)
        a = world.stack.drop.assert(world, Decimal)
        world.stack.add(a / b)
      end

      target.at("rem", "( A B -- R ): leaves the Remainder of two decimals.") do |world|
        b = world.stack.drop.assert(world, Decimal)
        a = world.stack.drop.assert(world, Decimal)
        world.stack.add(a % b)
      end

      target.at("dup", "( F -- F F ): duplicates the Form before cursor.", &.stack.dupl)
      target.at("drop", "( F -- ): drops the Form before cursor.", &.stack.drop)
      target.at("swap", "( A B -- B A ): swaps two Forms before cursor.", &.stack.swap)
      target.at("hydrate", "( S F -- ): opens Form with Stack set as the active stack.") do |world|
        form = world.stack.drop
        stack = world.stack.drop.assert(world, Block)
        world.enable(form, stack)
      end

      target.at("new", "( B -- I ): leaves an Instance of a Block.") do |world|
        block = world.stack.drop.assert(world, Block)
        block.instance.push(world)
      end

      target.at("sel", <<-END
    ( D A B -- A/B ): selects A (Determiner is truthy) or B
     (Determiner is falsey)
    END
      ) do |world|
        b = world.stack.drop
        a = world.stack.drop
        det = world.stack.drop
        det.sel(a, b).push(world)
      end

      target.at("<", "( A B -- S ): leaves whether one decimal is smaller than other.") do |world|
        b = world.stack.drop.assert(world, Decimal)
        a = world.stack.drop.assert(world, Decimal)
        Boolean[a < b].push(world)
      end

      target.at("same?", <<-END
    ( F1 F2 -- true/false ): leaves whether two Forms are the
     same (by reference for block, by value  for any other form).
    END
      ) do |world|
        b = world.stack.drop
        a = world.stack.drop
        Boolean.same?(a, b).push(world)
      end

      target.at("=", <<-END
    ( F1 F2 -- true/false ): leaves whether two Forms are equal
     (they may or may not be same forms, i.e., those for which
     `same?` would leave true).
    END
      ) do |world|
        b = world.stack.drop
        a = world.stack.drop
        Boolean[a == b].push(world)
      end

      target.at("block?", "( F -- true/false ): leaves whether Form is a block.") do |world|
        Boolean[world.stack.drop.is_a?(Block)].push(world)
      end

      target.at("word?", "( F -- true/false ): leaves whether Form is a word.") do |world|
        Boolean[world.stack.drop.is_a?(Word)].push(world)
      end

      target.at("quotedWord?", "( F -- true/false ): leaves whether Form is a quoted word.") do |world|
        Boolean[world.stack.drop.is_a?(QuotedWord)].push(world)
      end

      target.at("decimal?", "( F -- true/false ): leaves whether Form is a decimal.") do |world|
        Boolean[world.stack.drop.is_a?(Decimal)].push(world)
      end

      target.at("quote?", "( F -- true/false ): leaves whether Form is a quote.") do |world|
        Boolean[world.stack.drop.is_a?(Quote)].push(world)
      end

      target.at("boolean?", "( F -- true/false ): leaves whether Form is a boolean.") do |world|
        Boolean[world.stack.drop.is_a?(Boolean)].push(world)
      end

      target.at("pushes", <<-END
    ( B N F -- ): creates a definition for Name in Block that
     pushes Form when resolved there.
    END
      ) do |world|
        form = world.stack.drop
        name = world.stack.drop
        block = world.stack.drop.assert(world, Block)
        block.at name, Entry.new(form)
      end

      target.at("opens", <<-END
    ( B N F -- ): creates a definition for Name in Block that
     opens Form when resolved there.
    END
      ) do |world|
        form = world.stack.drop
        name = world.stack.drop
        block = world.stack.drop.assert(world, Block)
        block.at name, OpenEntry.new(form)
      end

      target.at("submit", <<-END
    ( B N F -- ): changes the value form of an existing definition
     of Name in Block to Form, but keeps its resolution action
     (open/push).
    END
      ) do |world|
        form = world.stack.drop
        name = world.stack.drop
        block = world.stack.drop.assert(world, Block)
        unless entry = block.at?(name)
          name.die("cannot #submit forms to an entry that does not exist")
        end
        entry.submit(form)
      end

      target.at("entry:exists?", <<-END
    ( T N -- true/false ): leaves whether Table can fetch
     value for Name.
    END
      ) do |world|
        name = world.stack.drop
        block = world.stack.drop.assert(world, ReadableTable)
        Boolean[block.has?(name)].push(world)
      end

      target.at("entry:fetch", "( B N -- F ): leaves the value Form under Name in Block's table.") do |world|
        name = world.stack.drop
        block = world.stack.drop.assert(world, ReadableTable)
        block.at(name).push(world)
      end

      target.at("entry:isOpenEntry?", <<-END
    ( B N -- true/false ): leaves whether an entry called Name
     in Block is an open entry.
    END
      ) do |world|
        name = world.stack.drop
        block = world.stack.drop.assert(world, ReadableTable)
        Boolean[block.at(name).is_a?(OpenEntry)].push(world)
      end

      target.at("detach", <<-END
    ( B -- C ): makes a shallow copy of Block's tape, and
     leaves a Copy block with the tape copy set as Copy's tape.
    END
      ) do |world|
        world.stack.drop.assert(world, Block).detach.push(world)
      end

      target.at("attach", "( O B -- ): replaces the tape of Block with Other's tape.") do |world|
        block = world.stack.drop.assert(world, Block)
        other = world.stack.drop.assert(world, Block)
        block.attach(other)
      end

      target.at("fromLeft", "( B I -- E ): leaves Index-th Element in Block from the left.") do |world|
        index = world.stack.drop.assert(world, Decimal)
        block = world.stack.drop.assert(world, Block)
        block.at(index.to_i).push(world)
      end

      target.at("charCount", "( Q -- N ): leaves N, the amount of characters in Quote") do |world|
        quote = world.stack.drop.assert(world, Quote)
        Decimal.new(quote.string.size).push(world)
      end

      target.at("count", "( B -- N ): leaves N, the amount of elements in Block.") do |world|
        block = world.stack.drop.assert(world, Block)
        count = Decimal.new(block.count)
        count.push(world)
      end

      target.at("|at", "( B -- N ): leaves N, the position of the cursor in Block.") do |world|
        block = world.stack.drop.assert(world, Block)
        cursor = Decimal.new(block.cursor)
        cursor.push(world)
      end

      target.at("|to", "( B N -- ): moves the cursor in Block to N.") do |world|
        cursor = world.stack.drop.assert(world, Decimal)
        block = world.stack.drop.assert(world, Block)
        block.to(cursor.to_i)
      end

      target.at("cherry", <<-END
    ( [ ... E | ... ]B -- [ ... | ... ]B -- E ): drops Block
     and Element before cursor in Block (and moves cursor back
     once), leaves Element.
    END
      ) do |world|
        world.stack.drop.assert(world, Block).drop.push(world)
      end

      target.at("shove", <<-END
    ( [ ... | ... ]B E -- [ ... E | ... ]B -- ): adds Element
     before cursor in Block (and moves cursor forward once),
     drops both.
    END
      ) do |world|
        world.stack.drop.push(world.stack.drop.assert(world, Block))
      end

      target.at("top", "( [ ... F | ... ]B -- F ): leaves the top Form in Block.") do |world|
        block = world.stack.drop.assert(world, Block)
        block.top.push(world)
      end

      target.at("mergeTables") do |world|
        donor = world.stack.drop.assert(world, Block)
        recpt = world.stack.drop.assert(world, Block)
        recpt.merge_table!(with: donor)
      end

      target.at("reportError") do |world|
        world.report(world.stack.drop.assert(world, Form::Died))
      end

      target.at("monotonic", "( -- Mt ): leaves milliseconds time of monotonic clock") do |world|
        Decimal.new(Time.monotonic.total_milliseconds).push(world)
      end

      target.at("echo", "( F -- ): shows Form in the console.") do |world|
        quote = world.stack.drop.enquote(world)
        puts quote.string
      end

      target.at("readLine", <<-END
    ( Pf -- Aq true/false ): prompts the user with Prompt form.
     Leaves Answer quote, and an accepted (true) / rejected (false)
     bool. If rejected, Answer quote is empty.
    END
      ) do |world|
        prompt = world.stack.drop.enquote(world)
        answer = Readline.readline(prompt.string)
        Quote.new(answer || "").push(world)
        Boolean[!!answer].push(world)
      end

      target.at("enquote", "( F -- Qr ): leaves Quote representation of Form.") do |world|
        world.stack.drop.enquote(world).push(world)
      end

      target.at("die", "( D -- ): dies with Details quote.") do |world|
        raise Form::Died.new(world.stack.drop.assert(world, Quote).string)
      end

      target.at("stitch", "( Q1 Q2 -- Q3 ): quote concatenation.") do |world|
        b = world.stack.drop.assert(world, Quote)
        a = world.stack.drop.assert(world, Quote)
        world.stack.add(a + b)
      end

      target.at("ls", "( B -- Nb ): gathers all table entry names into Name block.") do |world|
        block = world.stack.drop.assert(world, Block)
        result = Block.new
        block.ls.each do |form|
          result.add(form)
        end
        result.push(world)
      end

      target.at("reparent", <<-END
    ( C P -- C ): changes the parent of Child to Parent. Checks
     for cycles which can hang the interpreter, therefore is
     O(N) where N is the amount of Parent's ancestors.
    END
      ) do |world|
        pb = world.stack.drop.assert(world, Block)
        cb = world.stack.top.assert(world, Block)

        # Check for cycles. I'm having a hard time thinking
        # about this, so idk if this really works for them
        # smart cases.
        visited = [cb]
        current = pb
        while current
          if current.in?(visited)
            cb.die("this reparent introduces a cycle")
          end
          visited << current
          current = current.parent?
        end

        cb.parent = pb
      end

      target.at("slurp", <<-END
    ( B Q -- B ): parses Quote and adds all forms from Quote
     to Block.
    END
      ) do |world|
        source = world.stack.drop.assert(world, Quote)
        block = world.stack.top.assert(world, Block)
        block.slurp(source.string)
      end

      target.at("orphan", "( -- O ): Leaves an Orphan (a parent-less block).") do |world|
        Block.new.push(world)
      end

      target.at("orphan?", "( B -- true/false ): leaves whether Block is an orphan") do |world|
        Boolean[!world.stack.drop.assert(world, Block).parent?].push(world)
      end

      target.at("desc", "( F -- Hq ): leaves the description of Form.") do |world|
        quote = Quote.new(world.stack.drop.desc)
        quote.push(world)
      end

      target.at("nap", "( Nms -- ): sleeps for N decimal milliseconds.") do |world|
        sleep world.stack.drop.assert(world, Decimal).to_i.milliseconds
      end

      # File system ------------------------------------------

      target.at("fs:exists?", "( Pq -- true/false ): leaves whether Path quote exists.") do |world|
        path = world.stack.drop.assert(world, Quote)
        status = File.exists?(path.string)
        Boolean[status].push(world)
      end

      target.at("fs:readable?", "( Pq -- true/false ): leaves whether Path quote is readable.") do |world|
        path = world.stack.drop.assert(world, Quote)
        status = File.readable?(path.string)
        Boolean[status].push(world)
      end

      target.at("fs:dir?", <<-END
    ( Pq -- true/false ): leaves whether Path quote exists and
     points to a directory.
    END
      ) do |world|
        path = world.stack.drop.assert(world, Quote)
        status = Dir.exists?(path.string)
        Boolean[status].push(world)
      end

      target.at("fs:file?", <<-END
    ( Pq -- true/false ): leaves whether Path quote exists and
     points to a file.
    END
      ) do |world|
        path = world.stack.drop.assert(world, Quote)
        status = File.file?(path.string)
        Boolean[status].push(world)
      end

      target.at("fs:symlink?", <<-END
    ( Pq -- true/false ): leaves whether Path quote exists and
     points to a symlink.
    END
      ) do |world|
        path = world.stack.drop.assert(world, Quote)
        status = File.symlink?(path.string)
        Boolean[status].push(world)
      end

      target.at("fs:touch", "( P -- ): creates a file at Path.") do |world|
        path = world.stack.drop.assert(world, Quote)
        File.touch(path.string)
      end

      target.at("fs:read", "( F -- C ): reads and leaves Contents of File") do |world|
        path = world.stack.drop.assert(world, Quote)
        contents = File.read(path.string)
        Quote.new(contents).push(world)
      end
    end
  end
end
