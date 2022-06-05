# A tape is an array with an insertion/deletion point (the cursor).
class Tape(T)
  protected getter array = [] of T

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
  def empty?
    count.zero?
  end

  # Returns the amount of elements in the tape.
  def count
    array.size
  end

  # Returns whether the cursor is in the beginning of the tape.
  def at_begin?
    cursor.zero?
  end

  # Returns whether the cursor is in the end of the tape.
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
  def peek?
    at?(cursor)
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
  def last?
    at?(count - 1)
  end

  # Returns the element at *index* if *index* is in bounds,
  # else nil.
  def at?(index)
    array[index] if index.in?(0...count)
  end

  # Sets the element at *index* to *elem* if *index* is in
  # bounds, else returns nil.
  def at?(index, set elem)
    array[index] = elem if index.in?(0...count)
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

  # Yields every element to the block.
  delegate :each, to: array

  # Yields elements after the cursor to the block.
  def rest
    (cursor...count).each do |index|
      yield array[index]
    end
  end

  # Returns a new tape with elements processed by the block.
  def map
    Tape(T).new(array.map { |element| (yield element).as(T) }, cursor)
  end

  def to_s(io)
    return io << "|" if empty?

    iter = array.each

    if at_begin?
      io << "| "
      iter.join(io, ' ') do |element, io|
        executed = exec_recursive(:to_s) do
          io << element
        end
        io << "reflection" unless executed
      end
    elsif at_end?
      iter.join(io, ' ') do |element, io|
        executed = exec_recursive(:to_s) do
          io << element
        end
        io << "reflection" unless executed
      end
      io << " |"
    else
      iter.first(cursor).join(io, ' ') do |element, io|
        executed = exec_recursive(:to_s) do
          io << element
        end
        io << "reflection" unless executed
      end
      io << " | "
      iter.join(io, ' ') do |element, io|
        executed = exec_recursive(:to_s) do
          io << element
        end
        io << "reflection" unless executed
      end
    end
  end

  def_equals_and_hash array, cursor
end
