require "./substrate"

module Novika
  # A `Substrate` with an integer cursor.
  struct Tape(T)
    protected getter substrate : Substrate(T)

    # Returns the cursor position.
    getter cursor : Int32

    def initialize(@substrate : Substrate(T) = Substrate(T)[], @cursor = substrate.count)
    end

    # Creates a tape from an existing array of *elements*, which
    # will be used as the underlying container for `Substrate`.
    # This means that all mutations of substrate will be performed
    # on the *elements* array, and vice versa.
    def self.for(elements : Array(T))
      Tape.new(Substrate.for(elements))
    end

    # Initializes a tape with *elements*.
    def self.[](*elements)
      Tape.new(Substrate[*elements])
    end

    # See the same method in `Substrate`.
    delegate :at?, :each, :count, to: substrate

    # Returns whether this tape is empty (has no elements).
    def empty?
      count.zero?
    end

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

    # Adds elements before cursor in *elements* to this tape.
    # Advances the cursor.
    def paste(elements : Tape(T))
      Tape.new(
        substrate.unsafe_paste(elements.substrate,
          index: cursor,
          other_start: 0,
          other_insert_count: elements.cursor
        ), cursor + elements.cursor
      )
    end

    # Removes the element before the cursor, and moves the cursor
    # back once. Returns the resulting tape.
    def drop?
      Tape.new(substrate.delete?(cursor - 1) || return, cursor - 1)
    end

    # Adds element after cursor without moving the cursor.
    def inject(element)
      Tape.new(substrate.insert?(cursor, element).not_nil!, cursor)
    end

    # Drops and returns the element after cursor.
    def eject?
      element = substrate.at?(cursor) || return

      {Tape.new(substrate.delete?(cursor).not_nil!, cursor), element}
    end

    # Returns the element after cursor and moves the cursor forward.
    def thru?
      element = substrate.at?(cursor) || return

      {Tape.new(substrate, cursor + 1), element}
    end

    # Replaces this tape's substrate with other. *cursor* is
    # left where it was in self if it fits, else is moved to
    # the end.
    def resub(other)
      substrate.deref

      Tape.new(other.substrate.copy, Math.min(cursor, other.count))
    end

    # See `Substrate#map!`.
    def map!
      Tape.new(substrate.map! { |form| yield form }, cursor)
    end

    # See `Substrate#sort_using!`
    def sort_using!(cmp : T, T -> Int32)
      Tape.new(substrate.sort_using!(cmp), cursor)
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
