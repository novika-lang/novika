# A tape is an array with an insertion/deletion point (the cursor).
class Tape(T)
  protected getter array : Array(T) = [] of T

  # Returns the position of cursor over the tape.
  getter cursor = 0

  # Initializes an empty tape.
  def initialize
  end

  protected def initialize(@array, @cursor = array.size)
  end

  # Adds elements from *list* to a new tape.
  def self.[](*list : T) forall T
    Tape(T).new.tap do |tape|
      list.each { |element| tape.add(element) }
    end
  end

  # Returns a shallow (tape class and internal array) copy
  # of *tape*.
  def self.borrow(tape : Tape(T)) forall T
    Tape(T).new(tape.array.dup, tape.cursor)
  end

  # Moves the cursor to *index* if *index* is in bounds.
  #
  # ```
  # tape = Tape[1, 2, 3]
  # tape           # 1 2 3 |
  # tape.to?(0)    # | 1 2 3
  # tape.to?(2)    # 1 2 | 3
  # tape.to?(-100) # 1 2 | 3
  # tape.to?(100)  # 1 2 | 3
  # ```
  def to?(index)
    @cursor = index if index.in?(0..count)
  end

  # Returns the part of tape before the cursor (empty if none).
  #
  # ```
  # tape = Tape[1, 2, 3]
  # tape.to?(2) # 1 2 | 3
  # tape.pre    # 1 2 |
  # tape.to?(0) # | 1 2 3
  # tape.pre    # |
  # ```
  def pre
    Tape(T).new(array[...cursor]? || [] of T)
  end

  # Returns the part of tape after the cursor (empty if none).
  #
  # ```
  # tape = Tape[1, 2, 3]
  # tape.to?(2)          # 1 2 | 3
  # tape.post            # 3 |
  # tape.to?(tape.count) # 1 2 3 |
  # tape.post            # |
  # ```
  def post
    Tape(T).new(array[cursor..]? || [] of T)
  end

  # Returns whether the tape is empty.
  @[AlwaysInline]
  def empty?
    count.zero?
  end

  # Returns the amount of elements in the tape.
  @[AlwaysInline]
  def count
    array.size
  end

  # Returns whether the cursor is in the beginning of the tape.
  @[AlwaysInline]
  def at_begin?
    cursor.zero?
  end

  # Returns whether the cursor is in the end of the tape.
  @[AlwaysInline]
  def at_end?
    cursor == count
  end

  # Returns the element immediately preceding the cursor.
  #
  # ```
  # tape = Tape[1, 2, 3]
  # tape        # 1 2 3 |
  # tape.top?   # 3
  # tape.to?(0) # | 1 2 3
  # tape.top?   # nil
  # ```
  @[AlwaysInline]
  def top?
    at?(cursor - 1)
  end

  # Returns the element immediately following the cursor, or
  # nil if none.
  #
  # ```
  # tape = Tape[1, 2, 3]
  # tape        # 1 2 3 |
  # tape.peek?  # nil
  # tape.to?(2) # 1 2 | 3
  # tape.peek?  # 3
  # ```
  @[AlwaysInline]
  def peek?
    at?(cursor)
  end

  # Returns the element immediately preceding the cursor, and
  # advances the cursor forward by one. Returns nil if cursor
  # will advance out of tape bounds.
  @[AlwaysInline]
  def next?
    array.unsafe_fetch(cursor.tap { @cursor += 1 }) if cursor < count
  end

  # Returns the last element in the tape if it has one,
  # otherwise nil.
  #
  # ```
  # tape = Tape[1, 2, 3]
  # tape        # 1 2 3 |
  # tape.last?  # 3
  # tape.to?(2) # 1 2 | 3
  # tape.last?  # 3
  # ```
  @[AlwaysInline]
  def last?
    at?(count - 1)
  end

  # Returns the element at *index* if *index* is in bounds,
  # else nil.
  def at?(index)
    array.unsafe_fetch(index) if index.in?(0...count)
  end

  # Sets the element at *index* to *elem* if *index* is in
  # bounds, else returns nil.
  def at?(index, set elem)
    array.unsafe_put(index, elem) if index.in?(0...count)
  end

  # Adds *element* before the cursor, and moves the cursor
  # to the right.
  #
  # ```
  # tape = Tape[1, 2, 3]
  # tape        # 1 2 3 |
  # tape.add(4) # 1 2 3 4 |
  # tape.add(5) # 1 2 3 4 5 |
  # tape.to?(0) # | 1 2 3 4 5
  # tape.add(6) # 6 | 1 2 3 4 5
  # tape.add(7) # 6 7 | 1 2 3 4 5
  # ```
  def add(element)
    array.insert(cursor.tap { @cursor += 1 }, element)

    self
  end

  # Removes and returns the element immediately before the cursor,
  # and moves the cursor to the left.
  #
  # Returns nil if no elements ot the left.
  #
  # ```
  # tape = Tape[1, 2, 3]
  # tape        # 1 2 3 |
  # tape.drop?  # 1 2 |
  # tape.to?(0) # | 1 2
  # tape.drop?  # nil
  # tape.to?(1) # 1 | 2
  # tape.drop?  # | 2
  # ```
  def drop?
    array.delete_at(@cursor -= 1) unless at_begin?
  end

  # Merges this tape with *other*. Cursor is kept from *other*.
  def replace(other : Tape(T))
    @array = other.array
    @cursor = other.cursor
  end

  # Replaces the internal array with *other*, clamps the cursor
  # in bounds of *other*. If the cursor was in the end, it stays
  # in the end.
  #
  # ```
  # tape = Tape[1, 2, 3]
  # tape # 1 2 3 |
  # tape.replace([2, 3, 4, 5])
  # tape # 2 3 4 5 |
  # tape.replace([1, 2, 3])
  # tape        # 1 2 3 |
  # tape.to?(2) # 1 2 | 3
  # tape.replace([2, 3, 4, 5])
  # tape # 2 3 | 4 5
  # ```
  def replace(other)
    @cursor = at_end? ? other.size : cursor.clamp(0..other.size)
    @array = other
  end

  # Yields each element.
  delegate :each, to: array

  def to_s(io)
    return io << "|" if empty?

    iter = array.each

    if at_begin?
      io << "| "; iter.join(io, ' ')
    elsif at_end?
      iter.join(io, ' '); io << " |"
    else
      iter.first(cursor).join(io, ' '); io << " | "; iter.join(io, ' ')
    end
  end

  def_equals_and_hash array, cursor
end
