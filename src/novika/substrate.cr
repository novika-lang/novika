module Novika
  # Substrate is a fast, low-level copy-on-write wrapper for
  # an array.
  module Substrate(T)
    # Initializes an empty substrate.
    def self.[]
      RealSubstrate(T).new
    end

    # Initializes a substrate with *elements*.
    def self.[](*elements)
      for(elements.to_a)
    end

    # Initializes a substrate with *elements* as the underlying array.
    def self.for(elements : Array(T))
      RealSubstrate.new(elements)
    end

    # Same as `Array#each`.
    delegate :each, to: array

    # Unsafely fetches the element at *index*.
    def at!(index)
      array.unsafe_fetch(index)
    end

    # Returns the amount of elements in the array.
    def count
      array.size
    end

    # Returns the element at *index*. Returns nil if *index* is
    # out of bounds, i.e., *not* in `0 <= index < count`.
    def at?(index)
      at!(index) if index.in?(0...count)
    end

    # Splits this substrate in two at *index*. Returns the two
    # resulting substrates.
    #
    # This method is unsafe: it does not check whether *index*
    # is in bounds.
    def slice_at!(index)
      lhs = Array(T).new(index) { |i| at!(i) }
      rhs = Array(T).new(count - index) { |j| at!(index + j) }

      {RealSubstrate.new(lhs), RealSubstrate.new(rhs)}
    end

    # Returns the actual array.
    protected abstract def array

    # Adds *element* before *index*. Returns nil if *index* is
    # out of bounds (see  `at?`).
    abstract def insert?(at index, element)

    # Deletes the element at *index*. Returns nil if *index* is
    # out of bounds (see `at?`).
    abstract def delete?(at index)

    # Decrements the amount of references to this substrate.
    protected abstract def deref

    # Returns a copy of this substrate.
    abstract def copy

    # Replaces elements of this substrate with the result of the
    # block. If the result is nil, leaves the original element.
    abstract def map!(& : T -> T?)

    # Sorts elements of this substrate inplace, using a *cmp*
    # comparator proc for comparing two elements.
    abstract def sort_using!(cmp : T, T -> Int32)

    def ==(other)
      other.is_a?(Substrate) && array == other.array
    end
  end

  # Operates on an existing substrate array, not under its
  # control. "Becomes" `RealSubstrate`  with shallow copy of
  # the array upon the first mutatation.
  private struct RefSubstrate(T)
    include Substrate(T)

    protected getter res : RealSubstrate(T)

    def initialize(@res : RealSubstrate(T) = RealSubstrate(T).new)
      res.refs += 1
    end

    protected delegate :array, to: res

    # Makes a copy of the referenced substrate, and calls this
    # method on it.
    delegate :set?, :insert?, :delete?, :map!, :sort_using!, to: begin
      deref

      RealSubstrate.new(array.dup)
    end

    protected def deref
      res.refs -= 1
    end

    def copy
      RefSubstrate.new(res)
    end
  end

  # Real substrate: operates on a substrate array under its
  # control. Copying returns a `RefSubstrate`.
  private class RealSubstrate(T)
    include Substrate(T)

    protected getter array : Array(T)

    # Returns/allows to set the amount of references to this
    # substrate.
    protected property refs = 0

    protected def initialize(@array : Array(T) = [] of T)
    end

    # Introduces a mutation.
    #
    # If reference count is non-zero (someone watches us), a
    # copy is made and is modified. If reference count is zero
    # (no one watches us), this object is modified.
    protected def mutate
      object = refs.zero? ? self : RealSubstrate.new(array.dup)
      object.tap { yield object }
    end

    def insert?(at index, element)
      mutate &.array.insert(index, element) if index.in?(0..count)
    end

    def delete?(at index)
      mutate &.array.delete_at(index) if index.in?(0..count)
    end

    def map!(& : T -> T?)
      mutate do |mutee|
        mutee.count.times do |index|
          element = mutee.array.unsafe_fetch(index)
          if element = yield element
            mutee.array.unsafe_put(index, element)
          end
        end
      end
    end

    def sort_using!(cmp : T, T -> Int32)
      mutate do |mutee|
        mutee.array.sort! do |a, b|
          cmp.call(a, b)
        end
      end
    end

    protected def deref
      self.refs -= 1
    end

    def copy
      RefSubstrate.new(self)
    end
  end
end
