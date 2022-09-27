# Novika

<img src="img/logo.svg" align=right>

Novika is a novel interpreted programming language, somewhat related
to Forth, Red/Rebol, Self, and Lisp.

> Novika [organizes](doc/BlockOrg.pdf) and evaluates forms.

This branch is the most recent (10th) prototype implementation of Novika.

Most notable features of Novika include:

* It's weird, one of the weirdest languages you'd find. Brainfuck was a joke,
  but Novika isn't. Novika seems simple to explain (speaking from personal
  experience here), but in reality, it damn isn't. At the extremes, simplicity
  comes at a cost.

* Almost no syntax: Novika is tokenized, but there is not much syntax to talk
  about. There is only one kind of syntax error, missing closing bracket.

* Small amount of core *forms*: blocks, decimals (aka numbers), quotes (aka strings), booleans, and
  a few more. *Block* is something you are going to see a lot in Novika.

* Code is data, and data is code. Homoiconicity is a polluted term, but you knew
  this would be coming in such kind of language didn't you? :)

* As data, blocks can be arrays, or stacks with an insertion point, or dictionaries
  (ordered hash maps mapping form to form), or anything in-between. Blocks also
  hold continuations. Individual continuations are blocks as well. Each consists
  of two sub-blocks: the stack block (a block used as a stack), and a code block
  (the block whose contents is executed). See, blocks are everywhere.

* Blocks are also objects in Self sense of the word, if you manage to capture them.
  And at runtime, they may act as symbol tables for code in them. If seen as symbol
  tables, blocks are lexical in terms of hierarchy, but dynamic in terms of scope
  contents. In other words, the content of scopes does not get captured; instead,
  their hierarchy does and is exactly the *block hierarchy*.

* Runtime macros: you can access your caller and (literally) modify it so that it
  executes what you want next. Or do something to its stack. After all, everything
  is a block.

Yup. It's damn hard to even introduce.

## Examples

Sieve of Eratosthenes: prints prime numbers in [2; 120].

```novika
2 to: 120 ||-> [ $: n stack without: [ n /? ] cover n ] each: echo
```

First 100 Fizz buzz rounds:

```novika
1 to: 100 each: [
  [ [ 15 /? ] 'FizzBuzz'
    [  5 /? ] 'Buzz'
    [  3 /? ] 'Fizz'
  ] choose echo
]
```

A tiny DSL for counting average number:

```novika
[ ahead |before: [ decimal? not ] bi: sum count / ] @: avg:

avg: 1 2 3      echo "STDOUT: 2⏎"
avg: 100 4 6 5  echo "STDOUT: 28.75⏎"
```

`definfix` and `withInfixMath` DSL to create words with precedence, in
this case for evaluating simple math expressions. It's 35 lines if you
remove comments and empty lines, and 27 if you remove the examples.
Quite short for bootstrapping precedence parsing (but could be shorter,
I agree).

```novika
[ "( Cb B P N -- ): defines an infix operator in caller: assigns
   it given Precedence, and saves it under Name in caller, and
   in Context dict block (used for looking up information about
   the available operators). Code Block will be executed when
   this operator terminates."
  $: ctx @: code asDecimal $: prec asWord $: name

  ctx name this pushes "Register operator in the database block."

  ahead name [
    "This block is run when you *use* an operator."
    ahead $: caller

    "In this case, |before? will collect (group) until another
     operator has *less* precedence than we."
    caller [ ctx swap entry:flatFetch? [ .prec prec <= ] and ] |before? not
      => [ caller 1 |+ ]

    "When we've met end-of-block or an operator with less precedence,
     execute code block in the caller context, passing it all we've
     gathered so far.."
    caller reparent vals last code
  ] opens
] @: definfix


[
  0 $: _SUM
  1 $: _FACTOR
  2 $: _POWER

  [ ] $: _ctx

  "Save old (stack) operators. There are better ways, but this
   will do too. Note that these won't be available inside the
   block passed to withInfixMath: this could be a point to
   address in case this gets into the standard library."
   #+ here @: _+
   #- here @: _-
   #* here @: _*
   #/ here @: _/
  #** here @: _**

  #+     _SUM [ 2val _+  ] _ctx definfix
  #-     _SUM [ 2val _-  ] _ctx definfix
  #*  _FACTOR [ 2val _*  ] _ctx definfix
  #/  _FACTOR [ 2val _/  ] _ctx definfix
  #**  _POWER [ 2val _** ] _ctx definfix

  this reparent
] @: withInfixMath


[ [ 3 * 8 + 5 ] + 2 + 3 ] withInfixMath val echo "STDOUT: 34⏎"
[ [ 3 * 8 + 5 ] + 2 + 3 ] withInfixMath val echo "STDOUT: 34⏎"
[ 100 * [ 1 / 4 ] ] withInfixMath val echo "STDOUT: 25⏎"
[ 2 + 3 ** 8 + 6 * 3 ] withInfixMath val echo "STDOUT: 6581⏎"
"...etc. Any simple math expression will work."


"Fragments between the operators are blocks of their own right,
 thereby allowing:"

[ "Leaves a 2D point object." $: x ahead thruVal $: y this ] @: @

100 @ 200 $: A
300 @ 50  $: B

"Euclidean distance between A and B:"
[ [B.x - A.x] ** 2 + [B.y - A.y] ** 2 ] withInfixMath val sqrt echo "STDOUT: 250⏎"
```

## Using Novika as a library

I don't know why you would need that, but there is some API and if you don't inject the
features, you'd get bare-bones Novika. But then you'd be better off with splitting a
string on whitespaces and fetching each word from a hashmap.

```yml
dependencies:
  novika:
    github: novika-lang/novika
```

## Is it serious?

Yes and no. It's a project done with smart look on the face, but
honestly, I see little or no ways Novika can actually be used in
practice, mainly in money-making practice. So it's pure language
research and experimentation thingy for now.

## How can I build and run Novika?

The [latest release](https://github.com/novika-lang/novika/releases/latest) is available. It should just work.

Building:

1. Clone or download his repo: `git clone https://github.com/novika-lang/novika`.
2. Make sure your working directory is this repo.
3. On Windows, get rid of `shard.yml` and rename `shard.windows.yml` to `shard.yml`
  (that's smart huh?).
4. On Windows, type the following command:
    `shards build --without-development --release --progress --no-debug -Dnovika_frontend`

    On Unix, type the following command:
    `shards build --without-development --release --progress --no-debug -Dnovika_frontend -Dnovika_console -Dnovika_readline`.

Wondering about the `-D`s?

* `-Dnovika_frontend`: enables Novika frontend. If you run `./bin/novika`, this is the frontend
  speaking to you, and it's the same frontend that's going to collect and feed the right files to
  a Novika engine it created.

* `-Dnovika_readline`: use linenoise instead of `gets`.

* `-Dnovika_console`: enables the default console feature implementation which uses
  [termbox2](https://github.com/homonoidian/termbox2.cr). The latter doesn't support Windows so
  you'd also have to drop it.

## How can I play with Novika?

Hint: look into the world directory. It works only with outdated Novika though, beware.

`examples/` directory is the best place to go. There, the best example
is `snake.nk`. Most of the code is documented, but that documentation
uses some Novika terms that require clarification (mainly because I'm
also just exploring the language, so explaining it will require some time).
Plus, there is a lot of implicit expectations in code (this would be
partially resolved later with a dynamic (runtime) type check system),
and in docs too.

You can run REPL with: `novika core repl.nk`

## How can I learn Novika?

> Docs are in progress, but not really.

I don't know if you should, but you can contact me at `homonoidian@yandex.ru`
and maybe, just maybe, we'll take a look. I won't be able to handle a lot of
people because I'm a hardcore text message introvert whose "battery" discharges
quite quickly, but there is a slight chance.

## Syntax highlighting

There's a `sublime-syntax` file in `syn/`, for Sublime Text (I used ST 4).

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

* A mish-mash of everything. Specialization and strict separation
  of concerns helps thought, generalization doesn't. It doesn't
  make programs run fast either. The latter is a huge problem in
  Novika. It's very slow. Very.

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

* Mutation: Novika's take on mutation is very unsafe one. It's not
  one of those languages that surround you with a safety bubble
  from mutations, side effects, etc. Forget about that.

**Remember these are the language's cons**. If you want an objective
critique of the language, you'd need to take these into account. But
don't be toxic taking criticism as specification.

## Language notes

These are a bit outdated. Look into the Wiki, perhaps it would be updated,
perhaps it would not.

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

* Blocks consist of a *tape* and a *dictionary*.
  * Block tape is an ordered list plus an insertion point called *cursor*.
  * Block dictionary is an ordered hash map mapping form to form.

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

Theory:

* Look at the source. Explore `crystal docs`.

* Read [Novika's Approach To Loops](https://github.com/novika-lang/novika/blob/rev10/doc/novikas-approach-to-loops.md)
  and suggest fixes for my spelling and grammar mistakes!

Practice:

* `crystal run novika.cr -Dnovika_frontend -Dnovika_console -Dnovika_readline -- core file.nk`.
   Make it break. See where and why. Easy, huh? Build in release. `flamegraph` it?

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

1. Fork it (<https://github.com/novika-lang/novika/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

* [homonoidian](https://github.com/homonoidian) - creator and maintainer
