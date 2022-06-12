module Novika::Primitives
  # Populates *target* with Novika primitives.
  def self.inject(into target)
    target.at(Word.new("true"), True.new)
    target.at(Word.new("false"), False.new)

    # Leaves the Prototype of Block: ( B -- P ).
    target.at("prototype") do |world|
      block = world.stack.drop.assert(Block)
      block.prototype.push(world)
    end

    # Leaves the Parent of Block: ( B -- P ).
    target.at("parent") do |world|
      block = world.stack.drop.assert(Block)
      block.parent.push(world)
    end

    # Pushes the Continuations block: ( -- Cs ).
    target.at("conts") do |world|
      world.conts.push(world)
    end

    # Pushes the current continuation Block: ( -- B ). Dirty!
    target.at("this") do |world|
      world.block.push(world)
    end

    # Pushes the active Stack (stack of the CC): ( -- S ).
    target.at("stack") do |world|
      world.stack.push(world)
    end

    # Leaves the Sum of two decimals: ( A B -- S ).
    target.at("+") do |world|
      b = world.stack.drop.assert(Decimal)
      a = world.stack.drop.assert(Decimal)
      world.stack.add(a + b)
    end

    # Leaves the Difference of two decimals: ( A B -- D ).
    target.at("-") do |world|
      b = world.stack.drop.assert(Decimal)
      a = world.stack.drop.assert(Decimal)
      world.stack.add(a - b)
    end

    # Leaves the Product of two decimals: ( A B -- P ).
    target.at("*") do |world|
      b = world.stack.drop.assert(Decimal)
      a = world.stack.drop.assert(Decimal)
      world.stack.add(a * b)
    end

    # Leaves the Quotient of two decimals: ( A B -- Q ).
    target.at("/") do |world|
      b = world.stack.drop.assert(Decimal)
      a = world.stack.drop.assert(Decimal)
      world.stack.add(a / b)
    end

    # Leaves the Remainder of two decimals: ( A B -- R ).
    target.at("rem") do |world|
      b = world.stack.drop.assert(Decimal)
      a = world.stack.drop.assert(Decimal)
      world.stack.add(a % b)
    end

    # Duplicates the Form before cursor: ( F -- F F ).
    target.at("dup", &.stack.dupl)

    # Drops the Form before cursor: ( F -- ).
    target.at("drop", &.stack.drop)

    # Swaps two Forms before cursor: ( A B -- B A ).
    target.at("swap", &.stack.swap)

    # Opens Form with Stack set as the active stack: ( S F -- ).
    target.at("hydrate") do |world|
      form = world.stack.drop
      stack = world.stack.drop.assert(Block)
      world.continue(form, stack)
    end

    # Leaves an Instance of a Block: ( B -- I ).
    target.at("new") do |world|
      block = world.stack.drop.assert(Block)
      block.instance.push(world)
    end

    # Selects A (Determiner is truthy) or B (Determiner is
    # falsey): ( D A B -- A/B ).
    target.at("sel") do |world|
      b = world.stack.drop
      a = world.stack.drop
      det = world.stack.drop
      det.sel(a, b).push(world)
    end

    # Leaves whether one decimal is smaller than other: ( A B -- S ).
    target.at("<") do |world|
      b = world.stack.drop.assert(Decimal)
      a = world.stack.drop.assert(Decimal)
      Boolean[a < b].push(world)
    end

    # Leaves whether two Forms are the same (by reference for
    # block, by value  for any other form): ( F1 F2 -- true/false ).
    target.at("same?") do |world|
      b = world.stack.drop
      a = world.stack.drop
      Boolean.same?(a, b).push(world)
    end

    # Creates a definition for Name in Block that pushes Form
    # when resolved there: ( B N F -- ).
    target.at("pushes") do |world|
      form = world.stack.drop
      name = world.stack.drop
      block = world.stack.drop.assert(Block)
      block.at name, Entry.new(form)
    end

    # Creates a definition for Name in Block that opens Form
    # when resolved there: ( B N F -- ).
    target.at("opens") do |world|
      form = world.stack.drop
      name = world.stack.drop
      block = world.stack.drop.assert(Block)
      block.at name, OpenEntry.new(form)
    end

    # Changes the value form of an existing definition of Name
    # in Block to Form, but keeps its resolution action (open/
    # push).
    target.at("submit") do |world|
      form = world.stack.drop
      name = world.stack.drop
      block = world.stack.drop.assert(Block)
      unless entry = block.at?(name)
        name.die("cannot #submit forms to an entry that does not exist")
      end
      entry.submit(form)
    end

    # Looks up the value Form of Name in Block's table: ( B N -- F )
    target.at("get") do |world|
      name = world.stack.drop
      block = world.stack.drop.assert(ReadableTable)
      block.at(name).push(world)
    end

    # Makes a shallow copy of Block's tape, and leaves a Copy
    # block with the tape copy set as Copy's tape: ( B -- C ).
    target.at("detach") do |world|
      world.stack.drop.assert(Block).detach.push(world)
    end

    # Replaces the tape of Block with Other's tape: ( O B -- ).
    target.at("attach") do |world|
      block = world.stack.drop.assert(Block)
      other = world.stack.drop.assert(Block)
      block.attach(other)
    end

    # Leaves Index-th Element in Block from the left: ( B I -- E ).
    target.at("fromLeft") do |world|
      index = world.stack.drop.assert(Decimal)
      block = world.stack.drop.assert(Block)
      block.at(index.to_i).push(world)
    end

    # Leaves N, the amount of elements in Block: ( B -- N ).
    target.at("count") do |world|
      block = world.stack.drop.assert(Block)
      count = Decimal.new(block.count)
      count.push(world)
    end

    # Leaves N, the position of the cursor in Block: ( B -- N ).
    target.at("|at") do |world|
      block = world.stack.drop.assert(Block)
      cursor = Decimal.new(block.cursor)
      cursor.push(world)
    end

    # Moves the cursor in Block to N: ( B N -- ).
    target.at("|to") do |world|
      cursor = world.stack.drop.assert(Decimal)
      block = world.stack.drop.assert(Block)
      block.to(cursor.to_i)
    end

    # Drops Block and Element before cursor in Block (and moves
    # cursor back once), leaves Element:
    #
    # ( [ ... E | ... ]B -- [ ... | ... ]B -- E ).
    target.at("cherry") do |world|
      world.stack.drop.assert(Block).drop.push(world)
    end

    # Adds Element before cursor in Block (and moves cursor
    # forward once), drops both:
    #
    # ( [ ... | ... ]B E -- [ ... E | ... ]B -- )
    target.at("shove") do |world|
      world.stack.drop.push(world.stack.drop.assert(Block))
    end

    # Shows Form in the console: ( F -- )
    target.at("echo") do |world|
      world.stack.drop.echo(STDOUT)
    end
  end
end
