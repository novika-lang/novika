module Novika::Hook
  extend self

  # Returns the death hook name.
  #
  # Death hooks are used to catch deaths (known as exceptions
  # in other languages) in current block or in blocks below the
  # current block (nested blocks).
  #
  # By defining a death hook, you are basically wrapping the
  # contents of your block in an uncontrained (catch-all)
  # `try ... catch` or `begin ... rescue`.
  #
  # ```novika
  # [ getErrorDetails echo ] @: __died__
  #
  # 1 0 / "STDOUT: division by zero⏎"
  # ```
  def died : Word
    Word.new("__died__")
  end

  # Returns the word trap hook name.
  #
  # Word traps catch undefined words. Note that during word
  # resolution, word traps run *last*. That is, all parents
  # and friends of the block you're trying to resolve a word
  # in are searched, and only then traps are triggered in the
  # appropriate order.
  #
  # Traps can be nested: if one trap fails to resolve a word,
  # then an outer trap is triggered.
  #
  # The words *outer*, *inner*, *nested* etc. refer to the block
  # parent hierarchy. Initially, this means the hierarchy is
  # AST-like, but for reparented blocks (or blocks whose parent
  # hierarchy is changed otherwise), different traps will be
  # triggered in case of an undefined word.
  #
  # ```novika
  # [ 'The following word is undefined: ' swap ~ echo ] @: __trap__
  #
  # 1 2 + frobnicate "STDOUT: The following word is undefined: frobnicate⏎"
  # ```
  def trap
    Word.new("__trap__")
  end

  # Returns the block-to-word hook name.
  def as_word
    Word.new("__word__")
  end

  # Returns the block-to-color hook name.
  def as_color
    Word.new("__color__")
  end

  # Returns the block-to-quote hook name.
  def as_quote
    Word.new("__quote__")
  end

  # Returns the block-to-decimal hook name.
  def as_decimal
    Word.new("__decimal__")
  end

  # Returns the block-to-boolean hook name.
  def as_boolean
    Word.new("__boolean__")
  end

  # Returns the block-to-quoted word hook name.
  def as_quoted_word
    Word.new("__quotedWord__")
  end

  # Returns the block-to-byteslice hook name.
  def as_byteslice
    Word.new("__byteslice__")
  end

  # Returns the on-shove hook name.
  #
  # On-shove hooks trigger when the user tries to `shove` a
  # form into the block the hook is attached to. Note that
  # this doesn't necessarily mean literally using `shove`.
  #
  # For instance, simply typing `1 2 3` will shove 1, 2, 3
  # consequtively onto the stack. The latter is known as
  # *pushing*, since *shoving* is defined for a block-and-a-
  # form pair, while *pushing* is defined for a stack-and-a-
  # form-pair, where the stack is implicit.
  #
  # Defining an on-shove hook will allow you to change how
  # your block behaves when it's used as a stack and pushed
  # to, and how it behaves when it is shoved into.
  #
  # On-shove hook is complemented by `on_cherry`. See it to
  # learn more.
  def on_shove
    Word.new("__shove__")
  end

  # Returns the on-cherry hook name.
  #
  # On-cherry hooks trigger when the user tries to *cherry*
  # a form out of a block. This doesn't necessarily mean using
  # the word `cherry`, since e.g. the word `drop` and its
  # implicit counterpart *pop* is defined in terms of `cherry`.
  #
  # Defining an on-shove hook will allow you to change how
  # your block behaves when it's used as a stack and dropped/
  # popped from, and how it behaves when it is `cherry`d.
  #
  # On-shove hook is complemented by `on_shove` hook. See it
  # to learn more.
  #
  # The "Hello, World" of on-shove/on-cherry is defining a
  # *controlled stack*.
  #
  # ```novika
  # [
  #   [ ] $: _controlledStack
  #
  #   [ drop _controlledStack swap bi: ['Shove ' swap ~ echo] shove ] @: __shove__
  #   [ drop _controlledStack cherry dup 'Cherry ' swap ~ echo ] @: __cherry__
  #
  #   [ _controlledStack echo ] @: print
  # ] obj $: master
  #
  # master [ 1 2 + ] there
  # master.print
  # "STDOUT: Shove 1⏎"
  # "STDOUT: Shove 2⏎"
  # "STDOUT: Cherry 2⏎"
  # "STDOUT: Cherry 1⏎"
  # "STDOUT: Shove 3⏎"
  # "STDOUT: [ 3 ]⏎"
  # ```
  def on_cherry
    Word.new("__cherry__")
  end
end
