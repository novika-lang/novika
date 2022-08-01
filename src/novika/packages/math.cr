module Novika::Packages
  # Provides some basic math vocabulary.
  class Math
    include Package

    def self.id
      "math"
    end

    def inject(into target)
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
    end
  end
end
