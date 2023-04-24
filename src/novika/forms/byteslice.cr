module Novika
  struct Byteslice
    include Form

    # Holds the default preview string for byteslices.
    DEFAULT_PREVIEW = "byteslice"

    # Returns the preview string of this byteslice.
    getter preview : String

    # Returns whether this byteslice is mutable.
    getter? mutable : Bool

    # Initializes a byteslice from *bytes*.
    def initialize(@bytes : Bytes, @preview = DEFAULT_PREVIEW, @mutable = true)
    end

    # Initializes a byteslice form from the given *io*.
    def initialize(io : IO, preview = DEFAULT_PREVIEW, mutable = true)
      initialize(io.to_slice, preview, mutable)
    end

    def self.typedesc
      "byteslice"
    end

    # Returns the *index*-th byte.
    def at(index : Int32)
      byte = @bytes[index]? || die("index out of bounds")

      Decimal.new(byte)
    end

    # Returns a sub-slice starting at *b*-th byte, and
    # ending at *e*-th byte.
    #
    # The resulting byteslice *does not* preserve the
    # preview string of this byteslice.
    def at(b : Int32, e : Int32)
      b = Math.max(b, 0)
      e = Math.min(e, count - 1)
      Byteslice.new(@bytes[b..e], mutable: @mutable)
    end

    # Returns the amount of bytes in this byteslice.
    def count
      @bytes.size
    end

    def desc(io)
      to_s(io)
    end

    def to_s(io)
      io << "[" << @preview << ", consists of " << count << " "
      io << (@mutable ? "mutable" : "immutable")
      io << " byte(s)]"
    end

    # Returns the underlying byte slice.
    def to_unsafe : Bytes
      @bytes
    end

    # Returns the memory address where this byteslice points to.
    def address
      @bytes.to_unsafe.address
    end

    # Wraps the underlying byte slice in an IO.
    def to_io : IO::Memory
      IO::Memory.new(@bytes)
    end

    # Writes this byteslice to *io*.
    def write_to(io : IO)
      io.write(@bytes)
    end

    # Yields an IO to the block, then returns a raw bytes
    # form for it.
    def self.new(&)
      io = IO::Memory.new
      yield io
      new(io)
    end

    # Returns whether this byteslice points to the given *address*.
    def points_to?(address : UInt64)
      address == self.address
    end

    # Returns whether this and *other* byteslices point to the same
    # location in memory, and have the same mutability status.
    def same?(other : Byteslice)
      other.points_to?(address) && @mutable == other.mutable?
    end

    # Two byteslices are equal when their content is equal, and
    # their mutability statuses are equal.
    def_equals_and_hash @bytes, @mutable
  end
end
