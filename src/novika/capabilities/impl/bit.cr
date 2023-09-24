module Novika::Capabilities::Impl
  class Bit
    include Capability

    def self.id : String
      "bit"
    end

    def self.purpose : String
      "allows to interpret decimals as sequences of bits"
    end

    def self.on_by_default? : Bool
      true
    end

    def inject(into target : Block)
      target.at("bit:fromLeft", <<-END
      ( D I -- B ): leaves Index-th Bit from left in the given Decimal,
       represented as `0` or `1`. Dies if Decimal has a fractional part.
       The sign of decimal is ignored.

      Note: we consider the *left*most bit to be the most significant bit,
      and the *right*most bit the least significant bit. Leading zeroes
      do not count.

      ```
      0b00010001 0 bit:fromLeft leaves: 1
      0b00010001 1 bit:fromLeft leaves: 0
      0b00010001 2 bit:fromLeft leaves: 0
      0b00010001 3 bit:fromLeft leaves: 0
      0b00010001 4 bit:fromLeft leaves: 1
      ```
      END
      ) do |_, stack|
        index = stack.drop.a(Decimal).posint
        decimal = stack.drop.a(Decimal).int
        unless bit = decimal.nth_ms_bit?(index)
          index.die("bit index out of bounds")
        end
        bit.onto(stack)
      end

      target.at("bit:fromRight", <<-END
      ( D I -- B ): leaves Index-th Bit from right in the given Decimal,
       represented as `0` or `1`. Dies if Decimal has a fractional part.
       The sign of decimal is ignored.

      Note: we consider the *left*most bit to be the most significant bit,
      and the *right*most bit the least significant bit. Leading zeroes
      do not count.

      ```
      0b00010001 0 bit:fromRight leaves: 1
      0b00010001 1 bit:fromRight leaves: 0
      0b00010001 2 bit:fromRight leaves: 0
      0b00010001 3 bit:fromRight leaves: 0
      0b00010001 4 bit:fromRight leaves: 1
      ```
      END
      ) do |_, stack|
        index = stack.drop.a(Decimal).posint
        decimal = stack.drop.a(Decimal).int
        decimal.nth_ls_bit(index).onto(stack)
      end

      target.at("bit:count", <<-END
      ( D -- Bc ): leaves Bit count, the number of bits in the given
       Decimal. Dies if Decimal has a fractional part.

      ```
      0b00010001 bit:count leaves: 4
      ```
      END
      ) do |_, stack|
        decimal = stack.drop.a(Decimal).int
        decimal.bitcount.onto(stack)
      end

      target.at("bit:or", <<-END
      ( D D -- D ): combines two Decimal numbers using bitwise or, leaves
       the resulting Decimal. Dies if either of decimal has a fractional part.

      ```
      0b00010001
      0b10001000 bit:or leaves:
      0b10011001
      ```
      END
      ) do |_, stack|
        b = stack.drop.a(Decimal).int
        a = stack.drop.a(Decimal).int
        (a | b).onto(stack)
      end

      target.at("bit:and", <<-END
      ( D D -- D ): combines two Decimal numbers using bitwise and, leaves
       the resulting Decimal. Dies if either of decimal has a fractional part.

      ```
      0b10011001
      0b00011000 bit:and leaves:
      0b00011000
      ```
      END
      ) do |_, stack|
        b = stack.drop.a(Decimal).int
        a = stack.drop.a(Decimal).int
        (a & b).onto(stack)
      end

      target.at("bit:bits", <<-END
      ( D -- Bb ): leaves Bits block for the given Decimal, which contains
       the binary representation of the *absolute value* of Decimal, starting
       with the most-significant bit.

      ```
      0b10011001 bit:bits leaves: [ 1 0 0 1 1 0 0 1 ]
      ```
      END
      ) do |_, stack|
        decimal = stack.drop.a(Decimal).int
        bits = Block.new
        decimal.each_bit &.onto(bits)
        bits.onto(stack)
      end

      target.at("bit:fromBits", <<-END
      ( Bb -- D ): converts Bits block to a Decimal. Bits block should
       contain binary digits (represented by `0` or `1`), and should
       begin with the most significant bit.

      ```
      0b10011001 bit:bits leaves: [[ 1 0 0 1 1 0 0 1 ]]
                 bit:fromBits leaves: 0b10011001
      ```
      END
      ) do |_, stack|
        bits = stack.drop.a(Block)
        acc = Decimal.new(0)
        pow = Decimal.new(bits.count - 1)
        one = Decimal.new(1)
        two = Decimal.new(2)
        bits.each do |bit|
          acc += bit.a(Decimal).int.in(0..1) * two ** pow
          pow -= one
        end
        acc.onto(stack)
      end
    end
  end
end
