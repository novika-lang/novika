module Novika
  # A naïve object pool, inspired by:
  #
  # https://gist.github.com/floere/3121579
  struct ObjectPool(T)
    def initialize(@create : -> T, @clear : T -> T)
      @free = {} of UInt64 => T
      @used = {} of UInt64 => T
    end

    private def id(obj : T)
      obj.object_id
    end

    # Returns a free/new instance of the object.
    def acquire : T
      unless kv = @free.shift?
        obj = @create.call
        kv = {id(obj), obj}
      end
      @used.[]=(*kv)
    end

    # Clears the given *instance* of the object, and releases
    # it so that it can be acquired by someone else.
    def release(obj : T)
      @clear.call(obj)
      id = id(obj)
      @free[id] = obj
      @used.delete(id)
    end
  end
end
