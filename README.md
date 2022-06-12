# Novika

Novika is an interpreted programming language, somewhat related to
Forth, Red/Rebol, Self, and Lisp.

This branch is the most recent (10th) prototype implementation of Novika.

This implementation is slow (very slow) and buggy. Currently, it can't
even be used for experimentation, let alone production. Mainly due to
core components being relatively undeveloped/unexplored.

The repository is unorganized. Code is raw and naïve at times.
Beware. Help if you can. Poke around. There is little docs on
the language itself, so explore and infer :)

For an example of Novika code, see `basis.nk`, and observe how it
gradually grows the language's vocabulary.


## Language notes

- Novika has *words* and *blocks*. Together they are known as *forms*.
Forms are *enclosed* in blocks by being surrounded with `[]`s:

  ```novika
  [ 1 2 + ]
  ```

- Words are immutable. Block is the only mutable kind of form.

- Words are separated by whitespaces. In this sense, Novika is
  whitespace-sensitive. Word is an umbrella for:
  - Word: `foo bar +baz 2dup a.Ny.Comb-ina+t\iOn`
  - Quoted word: `#foo`
  - Number: `123`
  - Quote: `'hello world'`

- Comments = double quotes: `1 "I'm a comment" 2 +`

- Blocks consist of a *tape* and a *table*.
  - Block tape is an ordered list plus an insertion point called *cursor*.
  - Block table is an ordered hash map mapping form to form.

- `open` (opening) = evaluate (evaluating).

- Words have definitions. Definitions can be pushed onto the stack, or
  opened. Definitions are fetched from the block enclosing the word when
  that block is opened.

- If definition is not found in the enclosing block, the parent block
  (one that encloses the enclosing block) is checked, etc. When the
  parent block is reached and the definition is still not found, the
  `*fallback` word is opened in the original block, with quoted word
  on the stack.

- The described process as a whole is called *resolution*.

- All forms except words are pushed onto the stack. Stack holds
  intermediate results. Stack is a block. With `there`, custom
  stack block may be specified.

    ```novika
    [ ] [ 1 2 + ] there echo "[ 3 | ]"
    ```

- Blocks need to be opened explicitly unless they are under a word/
  definition that does that:

    ```novika
    [ 1 2 + ] open "3"

    [ 1 2 + ] @: 1+2

    1+2 "3"
    ```

- Blocks are objects. Blocks are instantiated upon opening. `this`
  pushes the instance. `this prototype` pushes the prototype block,
  which is the block you with your eyes in this example:

  ```novika
  [ $: y  $: x
    this
  ] @: newPoint

  0 0 newPoint "[ | . x y ]"
    #x . "todo, and .x later"
    #y . "todo, and .y later"
  ```

- `this` is also the current continuation, so it's dirty. Cursor
  there is placed before the currently opened word.

Working with the insertion point:

```novika
  [ 1 2 3 ] "[ 1 2 3 | ]"
  [ 1 2 3 ] [ <| ] there "[ 1 2 | 3 ]
  [ + ] there  "[ 3 | 3 ]"
  [ echo ] there "Prints 3 ;; [ | 3]"
  open "3"
```

## Installation

Wut?

## Usage

`shards build --release --production --progress --no-debug` and
every other switch you can come up with :)

Then `./bin/novika basis.nk`. If you want to type in some code,
type it at the end of basis.nk (UX/UI sucks huh?). I guess
you'd also want to remove whatever example code there is already
(currently the `1000 times:` thingy).

## Development

Look at source. Explore `crystal docs novika.cr`.

Then `crystal run novika.cr -- basis.nk`. Make it break. See
where and why. Easy, huh? Maybe `flamegraph` it?

## Contributing

1. Fork it (<https://github.com/homonoidian/novika/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [homonoidian](https://github.com/homonoidian) - creator and maintainer
