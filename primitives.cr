# Returns a block of Novika primitives.
def primitives
  Block.new.tap do |prims|
    prims.at("true", True.new)
    prims.at("false", False.new)

    prims.at("world") do |world|
      world.stack.add(world)
    end

    prims.at("/default") do |world|
      word = world.stack.drop
      word.die("undefined table property: #{word}")
    end

    prims.at("/died") do |world|
      details = world.stack.drop
      raise FormDied.new(String.build { |io| io << "Died: "; details.echo(io) })
    end

    prims.at("drop") do |world|
      world.stack.drop
    end

    prims.at("swap") do |world|
      a = world.stack.drop
      b = world.stack.drop
      world.stack.add(a)
      world.stack.add(b)
    end

    prims.at("dup") do |world|
      a = world.stack.drop
      world.stack.add(a)
      world.stack.add(a)
    end

    prims.at("+") do |world|
      b = world.stack.drop.assert(BigDecimal)
      a = world.stack.drop.assert(BigDecimal)
      world.stack.add(a + b)
    end

    prims.at("-") do |world|
      b = world.stack.drop.assert(BigDecimal)
      a = world.stack.drop.assert(BigDecimal)
      world.stack.add(a - b)
    end

    prims.at("*") do |world|
      b = world.stack.drop.assert(BigDecimal)
      a = world.stack.drop.assert(BigDecimal)
      world.stack.add(a * b)
    end

    prims.at("/") do |world|
      b = world.stack.drop.assert(BigDecimal)
      a = world.stack.drop.assert(BigDecimal)
      world.stack.add(a / b)
    end

    prims.at("rem") do |world|
      b = world.stack.drop.assert(BigDecimal)
      a = world.stack.drop.assert(BigDecimal)
      world.stack.add((a.to_big_i % b.to_big_i).to_big_d)
    end

    prims.at("<") do |world|
      b = world.stack.drop.assert(BigDecimal)
      a = world.stack.drop.assert(BigDecimal)
      world.stack.add(Boolean[a < b])
    end

    prims.at("same?") do |world|
      b = world.stack.drop
      a = world.stack.drop
      world.stack.add(
        Boolean.same?(a, b)
      )
    end

    prims.at("open") do |world|
      world.stack.drop.open(world)
    end

    prims.at("sel") do |world|
      b = world.stack.drop
      a = world.stack.drop
      det = world.stack.drop
      world.stack.add det.sel(a, b)
    end

    prims.at("fromLeft") do |world|
      index = world.stack.drop.assert(BigDecimal)
      block = world.stack.drop.assert(Block)
      block.at(index.to_i).push(world)
    end

    prims.at("join") do |world|
      b = world.stack.drop.assert(Quote)
      a = world.stack.drop.assert(Quote)
      world.stack.add a + b
    end

    prims.at("pull") do |world|
      name = world.stack.drop.assert(String)
      block = world.stack.drop.assert(Tabular)
      block.at(name).push(world)
    end

    prims.at("opens") do |world|
      form = world.stack.drop
      name = world.stack.drop.assert(String)
      block = world.stack.drop.assert(Block)

      entry = block.at?(name)
      if entry && entry.prevable? && form.is_a?(Block)
        form.at("prev", entry)
      end

      block.at(name, OpenEntry.new(form))
    end

    prims.at("pushes") do |world|
      form = world.stack.drop
      name = world.stack.drop.assert(String)
      block = world.stack.drop.assert(Block)
      block.at(name, form)
    end

    prims.at("submit") do |world|
      form = world.stack.drop
      name = world.stack.drop.assert(String)
      block = world.stack.drop.assert(Block)

      unless entry = block.at?(name)
        name.die("cannot #submit forms to an entry that does not exist")
      end

      entry.submit(form)
    end

    prims.at("|at") do |world|
      (world.stack.drop.assert(Block).cursor - 1).to_big_d.push(world)
    end

    prims.at("|to") do |world|
      index = world.stack.drop.assert(BigDecimal)
      block = world.stack.drop.assert(Block)
      block.to(index.to_i)
    end

    prims.at("shove") do |world|
      form = world.stack.drop
      world.stack.drop.assert(Block).add(form)
    end

    prims.at("cherry") do |world|
      world.stack.drop.assert(Block).drop.push(world)
    end

    prims.at("count") do |world|
      world.stack.drop.assert(Block).count.to_big_d.push(world)
    end

    prims.at("prototype") do |world|
      world.stack.drop.assert(Block).prototype.push(world)
    end

    prims.at("parent") do |world|
      world.stack.drop.assert(Block).parent.push(world)
    end

    prims.at("detach") do |world|
      world.stack.drop.assert(Block).detach.push(world)
    end

    prims.at("attach") do |world|
      dest = world.stack.drop.assert(Block)
      src = world.stack.drop.assert(Block)
      dest.attach(src)
    end

    prims.at("new") do |world|
      world.stack.drop.assert(Block).instance.push(world)
    end

    prims.at("echo") do |world|
      form = world.stack.drop
      form.echo(STDOUT)
    end
  end
end
