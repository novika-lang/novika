module Novika::Packages
  # Provides some basic math vocabulary.
  class Math
    include Package

    def self.id
      "math"
    end

    def inject(into target)
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

      target.at("round", "( D -- Dr ): leaves round Decimal.") do |world|
        decimal = world.stack.drop.assert(world, Decimal)
        Decimal.new(decimal.val.round).push(world)
      end

      target.at("trunc", "( D -- Dt ): leaves truncated Decimal.") do |world|
        decimal = world.stack.drop.assert(world, Decimal)
        Decimal.new(decimal.val.trunc).push(world)
      end

      target.at("rand", "( -- Rd ): random decimal between 0 and 1.") do |world|
        Decimal.new(rand).push(world)
      end
    end
  end
end
