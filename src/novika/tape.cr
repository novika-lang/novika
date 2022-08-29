require "./substrate"

module Novika
  # A `Substrate` with an integer cursor.
  struct Tape(T)
    protected getter substrate : Substrate(T)

    # Returns the cursor position.
    getter cursor : Int32

    def initialize(@substrate : Substrate(T) = Substrate(T)[], @cursor = substrate.count)
    end

    # Initializes a tape with *elements*.
    def self.[](*elements)
      Tape.new(Substrate[*elements])
    end

    # See the same method in `Substrate`.
    delegate :at?, :each, :count, to: substrate

    # Returns the element before the cursor.
    def top?
      at?(cursor - 1)
    end

    # Moves the cursor to *position*. Returns the resulting tape
    # on success, nil if position is out of bounds (see `Substrate#at?`).
    def to?(cursor position)
      Tape.new(substrate, position) if position.in?(0..count)
    end

    # Fetches the top element, and advances the cursor. Returns
    # the tuple `{tape, element}`, where *tape* is the resulting
    # tape. Returns nil if cursor will be out of bounds.
    def next?
      {Tape.new(substrate, cursor + 1), substrate.at!(cursor)} if cursor < count
    end

    # Adds *element* before the cursor, and advances the cursor.
    # Returns the resulting tape.
    def add(element)
      Tape.new(substrate.insert?(cursor, element).not_nil!, cursor + 1)
    end

    # Removes the element before the cursor, and moves the cursor
    # back once. Returns the resulting tape.
    def drop?
      Tape.new(substrate.delete?(cursor - 1) || return, cursor - 1)
    end

    # Replaces this tape's substrate with other. *cursor* is
    # left where it was in self if it fits, else is moved to
    # the end.
    def replace(other)
      substrate.deref

      Tape.new(other.substrate.copy, Math.min(cursor, other.count))
    end

    # See `Substrate#map!`.
    def map!
      Tape.new(substrate.map! { |form| yield form }, cursor)
    end

    # Slices this tape's substrate at cursor, returns the
    # two resulting tape halves.
    def slice : {Tape(T), Tape(T)}
      lhs, rhs = substrate.slice_at!(cursor)

      {Tape.new(lhs), Tape.new(rhs)}
    end

    # Returns a shallow copy of this tape.
    def copy
      Tape.new(substrate.copy, cursor)
    end

    def_equals_and_hash substrate, cursor
  end
end
