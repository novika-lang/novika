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
    def self.new
      io = IO::Memory.new
      yield io
      new(io)
    end
  end
end
