# Novika

Novika is a novel interpreted programming language, somewhat related
to Forth, Red/Rebol, Self, and Lisp.

* This branch is the most recent (10th) prototype implementation of Novika.

* The implementation is slow (very slow) and buggy.

* Code is raw and naïve at times. Beware.

* Help if you can. Poke around. There is little docs on the language
  itself, so explore and infer (but really, try `crystal docs`) :)

For use as a library:

```yml
dependencies:
  novika:
    github: homonoidian/novika
```

## How can I build and run Novika?

Currently, there is only one official way:

1. Clone or download his repo: `git clone https://github.com/homonoidian/novika`.
2. Make sure your working directory is this repo.
3. On Windows, get rid of `shard.yml` and rename `shard.windows.yml` to `shard.yml`
  (that's smart huh?).
4. Type the following command: `shards install --without-development`.
5. On Windows, type the following command:
    `shards build --release --progress --no-debug -Dnovika_frontend`

   On Unix, type the following command:
    `shards build --release --progress --no-debug -Dnovika_frontend -Dnovika_console -Dnovika_readline`.

Then `./bin/novika` to see the help message. `./bin/novika core YOUR-TEST-FILE.nk`
is a way to go if you want to type some Novika code yourself, or try `./bin/novika core hello.nk`
as the help message suggests, and see Novika in action. If you want to experience how slow
Novika really is (except the filesystem part), run `./bin/novika core playground.nk`.

## How can I play with Novika?

`examples/` directory is the best place to go. There, the best example
is `snake.nk`. Much of the code is documented, but that documentation
uses some Novika terms that require clarification (mainly because I'm
also just exploring the language, so explaining it will require some time).
Plus, there is a lot of implicit expectations in code (this would be
partially resolved later with a dynamic (runtime) type check system),
and in docs too.

You can run REPL with: `novika core repl.nk`

## Syntax highlighting

There's a `sublime-syntax` file in `syn/`, for Sublime Text (I used ST 3).

## Pros/cons

It so happens that I am writing Novika code from time to time,
so here's what I can say.

### Pros

It's too early to say. Brevity? Homoiconicity squared? I. e.,
runtime homoiconicity too? WTF?

> Of interest: see the `world/` directory for a stub Novika
> environment. In far future, Novika will look a bit like
> what you'd see there.
>
> Of interest: Novika seems to be one of the best languages to
> explain continations with. But I haven't tried yet, so... :)

### Cons

* Novika is one of the purest expressions of dynamism (or, more
 specifically, *doesn't-give-a-f\*ck-ism*), on par with maybe
 Forth, but in Forth it's more dangerous because it can make
 your computer explode (I'm joking, of course). Note that I only
 learned a bit of Forth's philosophy, and haven't written even
 a line of it for myself.
* If you write bad code, it'll break somewhere else, and throw
 you a hundred-line-long stack trace. At least it really shows
 where the error happened HUH?
* You'll have to train your intuition to find where an error occured
  (you'd be able to do it in one-two months), because *Novika doesn't
  show nor store line numbers and filenames*
  :) Maybe this will change, I mean it must change!
* Your brain will explode trying to keep track of the stack, them
  Forth critics say. In Novika, you'd also have to keep track of
  the so-called *cursor*, and, if that sounds easy, of the block
  that's used as the stack. Two-three months for this.
* Some words open your blocks with a new stack (e.g., `loop`),
  and some do not (e.g., `br`). This is mostly documented (and
  must be!), but sometimes may still cause a lot of confusion.

**Remember these are the language's cons**, not its complete
description.

## Language notes

* Novika has *words* and *blocks*. Together they are known as *forms*.
Forms are *enclosed* in blocks by being surrounded with `[]`s:

  ```novika
  [ 1 2 + ]
  ```

* Words are immutable. Block is the only mutable kind of form.

* Words are separated by whitespaces. In this sense, Novika is
  whitespace-sensitive. Word is an umbrella for:
  * Word: `foo bar +baz 2dup a.Ny.Comb-ina+t\iOn`
  * Quoted word: `#foo`
  * Number: `123`
  * Quote: `'hello world'`

* Comments = double quotes: `1 "I'm a comment" 2 +`

* Blocks consist of a *tape* and a *table*.
  * Block tape is an ordered list plus an insertion point called *cursor*.
  * Block table is an ordered hash map mapping form to form.

* `open` (opening) = evaluate (evaluating).

* Words have definitions. Definitions can be pushed onto the stack, or
  opened. Definitions are fetched from the block enclosing the word when
  that block is opened.

* If definition is not found in the enclosing block, the parent block
  (one that encloses the enclosing block) is checked, etc. When the
  parent block is reached and the definition is still not found, the
  `*fallback` word is opened in the original block, with quoted word
  on the stack.

* The described process as a whole is called *resolution*.

* All forms except words are pushed onto the stack. Stack holds
  intermediate results. Stack is a block. With `there`, custom
  stack block may be specified.

    ```novika
    [ ] [ 1 2 + ] there echo "[ 3 | ]"
    ```

* Blocks need to be opened explicitly unless they are under a word/
  definition that does that:

    ```novika
    [ 1 2 + ] open "3"

    [ 1 2 + ] @: 1+2

    1+2 "3"
    ```

* Blocks are objects. Blocks are instantiated upon opening. `this`
  pushes the instance. `this prototype` pushes the prototype block,
  which is the block you see with your eyes in this example:

  ```novika
  [ $: y $: x
    this
  ] @: newPoint

  1 2 newPoint $: pt
  pt echo "[ | . x y ]"
  pt -> x echo "1"
  pt -> y echo "2"
  ```

* `this` is also the current continuation, so it's dirty. Cursor
  there is placed before the currently opened word.

Working with the insertion point:

```novika
  [ 1 2 3 ] "[ 1 2 3 | ]"
  [ 1 2 3 ] [ <| ] there "[ 1 2 | 3 ]
  [ + ] there  "[ 3 | 3 ]"
  [ echo ] there "Prints 3 ;; [ | 3]"
  open "3"
```

## Development

Look at the source. Explore `crystal docs`.

Then `crystal run novika.cr -- core file.nk`. Make it break. See
where and why. Easy, huh? Build in release. `flamegraph` it?

Seriously, this is a huge TODO.

## What's a revision, for Novika?

It's a major reconsideration of the language's core ideas and core
code. Major is when you start with an empty directory.

Current revision (rev10) is pretty stable, but unbearably slow. This
is due to my naïve code, of course, but also due to Novika's design
itself. I'm not going to make any more compromises on the design
part though, so when it crystalizes (and it more or less did), there
are going to be thorough language specs.

And then we all will **embrace the design**. This could be Novika's
motto, huh? Do programming languages have mottos?

That is, further implementations (if they won't go nuclear) must
work hard to make the most stupid and naive code run relatively
fast. Everything else will follow.

## Contributing

1. Fork it (<https://github.com/homonoidian/novika/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

* [homonoidian](https://github.com/homonoidian) - creator and maintainer
