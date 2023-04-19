# Novika

<img src="img/logo.svg" align=right>

> A language that doesn't affect the way you think about programming, is not worth knowing.
> ­— Alan J. Perlis

Novika is a free-form, moldable, interpreted programming language.

## Hi!

Uhmm... yeah, I have no idea what the sentence above means either. But let me try to explain anyway :)

### Free-form

Novika has no syntax and no style. Novika is so free-form it cannot be pretty-printed *even at runtime*.

Novika is like simulating a house of LEGO blocks vs. simulating a house of huge concrete blocks, wood, and all that. The latter
is much easier to the computer, but the former offers unlimited flexibility: you can build only so much from huge concrete blocks,
woord, chairs and whatnot. With LEGO, it's another story — an infinite amount of possibilities before you.

### Moldable

You can mold it and therefore it is moldable. The more you use Novika, the more it becomes truly *yours*. It quickly gets personal!

### Interpreted

There's a little yellow gnome Kate sitting inside your monitor. She is reading the Novika code on the
screen — don't forget she has to flip it in her mind! She is telling the computer what to do — all that
on the go! Kate is slow but very flexible.

### How about something more formal?

Novika belongs to no single paradigm. Instead, I'd say it's a mix of functional, object-oriented, and procedural paradigms — although by no means am I an expert on such things.

Novika borrows from Lisp, Forth, and Factor — and takes inspiration from Self, Red/Rebol, and Smalltalk.

Novika blocks are closures and objects simultaneously — they can relate, talk, and encapsulate. Blocks are code, too. In Novika, data is code, and code is data. And what are objects? Objects are data (sort of!) — and therefore, code.

Blocks can form friendships with each other, become parents of one another, and intercept, well, anything — feel free to slap some Pythonesque dunders on top of all I've said!
The block tree (or the block graph, depending on how you look at it) is yours — you are free to take over it anytime.

The engine is yours, too — blocks are the code, and code is run by the engine.

Semantically, Novika is like Lisp *A* set in motion by Lisp *B* with the possibility of bidirectional communication — but with objects, stacks, and so, so much more!

And the syntax of Novika? Well, there is no syntax. That is to say, almost no syntax. Syntactically, Novika lies somewhere between Lisp and Forth. And Forth — Forth has no syntax.
The rest is yours to define!

### Trade-offs

Of course, I had to make some trade-offs to achieve such a peculiar arrangement!

#### Negative performance

*Wait, what?*

See, good compilers/interpreters live well in the positives. That is to say they remove irrelevant runtime. Bad compilers and “normal” interpreters live near zero, at the very least getting rid of the notion of parsing.

And what about Novika? Novika is deep in the negatives. Novika *parses* at runtime. Yup, you’ve heard it right.

Waging wars with FFI will give you performance, sure (that is, will move you closer to zero from the negative side!) But then, why not simply use C, Rust, Crystal, or any other fancy-schmancy programming language — especially if you're doing something *serious*?

#### Readability

*It's up to you.*

Maybe you want your code to look cryptic — so your friends think you’re a hacker or something. Novika will not stand in your way.

But wait, why is that? Why is Novika not *designed* to be readable? Isn't that popular nowadays?

See, in Novika, it is easy to make your code readable — even natural language-like. This ease, however, degrades performance. Even if Novika someday gets a JIT, writing natural-language-like code will still impose a performance penalty, however minuscule it will be. Again, it’s up to you. Either you have their syntax and their performance, or your syntax and your performance.

#### Big projects

*Never.*

I have no clue what big projects are, or what they need. There are enough smart people in this world already.

I would say Novika is an interesting experiment and a great personal project. Perhaps the language will grow into something bigger a few years from now. Most likely, however, it'll die. Maintaining a full-featured programming language in the 21st century is hard ­— there's just so much it must be able to do! Maintaining an innovative one — that's a thousand times harder.

## An objective evaluation

TL; DR: Novika is a great language for quickly *prototyping* things.

In fact, most of interpreted languages are.

1. When I say "prototyping", I mean the "shut up" kind of prototyping, when you're so angry you just don't want
   the language to complain! An unused variable, something that needs to be an object rather than a method to
   work properly, wrong types — you don't care (all caps!), and Novika understands.

2. This comes at a cost. For one, performance is not that great — ­and in Novika, it is terrible, much worse
   than even in Python or MRI. This is mainly due to my naïve code but also due to the fact that the language
   wasn't *designed* for performance — it was designed for seamless reflectivity and quick prototyping.

3. In the land of interpreted languages, errors are a terrible and soul-devouring beast which you truly don't want to encounter. In Novika,
   anything can just `'"helpful" explanation' die` and explode your whole program — at runtime, of course! And hope
   it at least says something useful.

4. Moderately sized projects become harder to maintain in the refactoring and bug-fixing sense. There are
   no automated tools to help you with anything except for search & replace — and your brain designing things
   right the first time, of course, which for most programmers (including myself) is almost never the case.

5. Novika is one of the few high-level languages which allow self-modification, and there are even multiple flavors
   of it. I won't list them here because if this wall of text didn't kill you yet, then it sure will would
   these flavors be here. Novika is extremely hard to optimize: while in other languages there is at least
   a clear-ish flow of control, in Novika, there isn't, for any piece of code can change its meaning at any
   point in time.

6. If you're still here, the best thing about Novika is that it's not PHP, Perl, or JavaScript when it
   comes to types. Things rarely take an argument of more than one type. No implicit conversion is ever
   done (as far as I remember!)

7. I like criticizing my projects, but remember to make your own judgement as
   well. After all, there are Python-people, Perl-people, Red-people, Scheme-people
   and even Forth-people — all sorts of weird people :) So why not Novika-people? Maybe you're one of them.

## Examples

Ordered by craziness!

1. Hello World:

```novika
'Hello World' echo
```

2. Factorial:

```novika
"Parentheses () do not mean anything in Novika. They're like single-character comments."

(5 to: 1) product "120"
```

3. Sieve of Eratosthenes: prints prime numbers in `[2; 120]`.

```novika
2 to: 120 ||-> [ $: n (stack without: [ n /? ]) asStack n ] each: echo
```

4. First 100 Fizz buzz rounds:

```novika
1 to: 100 each: [
  [ [ 15 /? ] 'FizzBuzz'
    [  5 /? ] 'Buzz'
    [  3 /? ] 'Fizz'
  ] choose echo
]
```

5. A tiny DSL for counting the average of a bunch of numbers:

```novika
[ ahead |beforeOrToEnd: [ decimal? not ] bi: sum count / ] @: avg:

avg: 1 2 3      echo "STDOUT: 2⏎"
avg: 100 4 6 5  echo "STDOUT: 28.75⏎"
```

6. Self-modification by indirection (i.e. the normies' one):

```novika
[ ' from A branch' ~ echo ] $: alpha
[ ' from B branch' ~ echo ] $: beta
[ ' from C branch' ~ echo ] $: gamma

alpha @: printIt

[ 'Hi' printIt

  (this -> [ alpha beta gamma ]) sample =: printIt
] @: selfModify

selfModify "Will print from any of the branches randomly..."
selfModify
selfModify
```

7. Self-modification by rewriting (i.e. the dirty but true one):

```novika
[ ' from A branch' ~ echo ] @: alpha
[ ' from B branch' ~ echo ] @: beta
[ ' from C branch' ~ echo ] @: gamma

[ 'Hi' alpha

  (this prototype) 2 [ drop ([ alpha beta gamma ] sample) ] |hydrate
] @: selfModify

selfModify "Will print from any of the branches randomly..."
selfModify
selfModify
```

Now, if you want to look at something a bit more elaborate, there's:

* A snake game [example](https://github.com/novika-lang/novika/blob/rev10/examples/snake.new.nk)
* A simple [documentation viewer](https://github.com/novika-lang/novika/blob/rev10/examples/docuview.nk)
* A [prompt](https://github.com/novika-lang/novika/blob/rev10/examples/lch-prompt.nk) that blinks in colors from the LCH color space
* A TDD-d [observable](https://github.com/novika-lang/novika/blob/rev10/examples/observable.nk)
* A [live REPL interface](https://github.com/novika-lang/novika/blob/rev10/examples/mathrepl.nk) to a DSL for infix math expressions

### Curious curiosities

Here's an example of *weird* Novika. I don't know if the following program qualifies as
*nondeterministic*, but Novika certainly supports nondeterministic programming as I understand
it, in that the evaluation of any program is controlled mainly by that very program and the
choices it may or may not make at runtime -- choices deterministic or not.

```novika
[ "( S B -- C ): safely creates a Continuation block
   from the given Stack and Block."
  new keep: [0 |to] newContinuation
] @: createContinuation

[
  [ 'Hey!' echo ]
  [ 'Bye!' echo ]
  [ 'Uhm...' echo ]
] $: drum

[ "Open a random block from the drum. "
  drum (0 randTo: [ drum count 1 - ]) fromLeft open
] @: spinTheDrum

[ $: probability

  [
    drop

    rand probability < =>
      [ "This will be the stack:" (this -> [ probability ])
        "This will be the block:" (this -> withProbabilitySpin)
        createContinuation
      ]

    "This will be the stack:" [ ]
    "This will be the block:" (this -> spinTheDrum)
    createContinuation
  ] continues
] @: withProbabilitySpin
```

It's pretty hard to explain, but basically, if you give `withProbabilitySpin`
a probability from 0 to 1, then it will:

1. `spinTheDrum` to open (aka execute, aka evaluate) a random block from `drum`.
2. Based on a random number, decide whether to open `withProbabilitySpin` again.
3. And so on...

What I'm showing you here can be done with recursion and first-order
functions, sure -- or with loops. But there are limits to how "non-deterministically"
recursion/loops can control the flow, and here, in Novika -- in Novika there are
no limits! (even though Novika is powered by a loop behind the scenes haha)

So, if you give `withProbabilitySpin` the probability `1`, it will
loop forever. To add to the above, it will indeed *loop*, not recurse.
That is, there won't be a call stack explosion!

If the probability is less than one, it will loop for an unknown
amount of times. At probability `0`, it won't loop at all.

```novika
1 withProbabilitySpin "(or 0, or 0.5, etc.)"
```

Feel free to play with the probability yourself!

## Installing Novika

Download and unpack the [latest release](https://github.com/novika-lang/novika/releases/latest) for your system.

1. If you don't want to do a system-wide install, simply use `bin/novika` *while in the directory of the release*.

2. Otherwise, move the `env` folder to your user's home directory, and rename it to `.novika`. Optionally, add `bin/novika` to your PATH.

**Note**: Novika is developed at a rather fast pace, and releases are made every month or so — therefore, the latest release will probably miss all them fancy features. I'd recommend you to build Novika from source.

## Building Novika from source

You will need to have [Crystal](https://crystal-lang.org/install/) installed.

1. Clone this repository:

```
git clone https://github.com/novika-lang/novika.git
```

2. Go there:

```
cd novika
```

### Windows

Follow these commands:

```
mv shard.yml shard.old.yml
mv shard.windows.yml shard.yml
shards build --without-development --release --progress --no-debug
```

### Linux

```
shards build --without-development --release --progress --no-debug -Dnovika_console -Dnovika_readline
```

### What do the `-D`s mean?

* `-Dnovika_readline`: use [linenoise](https://github.com/antirez/linenoise) instead of `gets` for `readLine`.
* `-Dnovika_console`: use [termbox2.cr](https://github.com/homonoidian/termbox2.cr) as the backend for capability *console*.  Otherwise, *console* won't be available. Since [termbox2](https://github.com/termbox/termbox2) doesn't support Windows, you have to drop the flag when compiling for/under it.

### What's next?

You can optionally add `bin/novika` to PATH, and/or create a symbolic link for `env` called `.novika` in your user's home directory, like so:

```
ln -s /path/to/novika/repo/env /home/<your-user>/.novika
```

I'd recommend you to run the tests with `bin/novika tests`. If something seems wrong, [file an issue](https://github.com/novika-lang/novika/issues/new).

## Running the examples

Try to run one of the [examples](#examples). Some of them contain instructions on how you can run them. In general, you can use:

```
bin/novika path/to/example.nk
```

If it's yelling at you in red that you need *console*, use:

```
bin/novika console path/to/example.nk
```

(unless you're on Windows; Novika on Windows doesn't support console yet)

## Playing with the REPL

To run the REPL, use:

```
bin/novika repl
```

To list all available words, use `la`:

```
>>> la
```

To see documentation for a particular word, use `help` followed by the word that you're interested in:

```
>>> help toOrphan
...
>>> help 123
decimal number 123
>>> help 'Who am I?'
quote 'Who am I?'
```

To get a string description of a thing's type, use `typedesc`:

```
>>> 123 typedesc
... 'decimal' ...
>>> ##foobar typedesc
... 'quoted word' ...
```

## Learning Novika

1. Explore files in `tests/` to see how various words can be used. Beware, however, that those are internal behavior tests — and most of the time, they aren't practical/particularly readable.
2. Explore `help` messages of various words. A less up-to-date but more convenient way to do the same is to read word documentation [here](https://novika-lang.github.io/words/).
3. Explore files in `env/core`, the language's standard library.
4. Explore the [Wiki](https://github.com/novika-lang/novika/wiki).

I know there aren't a lot of materials here nor anywhere that'd teach you the language. On the fundamental stuff, the language is so weird I can't even remember how it all came to be. And in general I have so much to say that I just don't know where to begin. Hopefully, there will be more stuff here someday.

Explore Novika as if it were an alien spaceship that accidentally fell on Earth, full of weird little yellow rotating yukoos. The aliens did not write on every button what it will do when you press it. And even if they did, what kind of language would they be using?!

## Contributing

First of all, thank you for even getting this far! Even if you didn't read the whole document, thank you. Seriously :)

### Where do I start?

1. First of all, the documentation for rev10 (i.e., this implementation) is available [here](https://novika-lang.github.io/novika/).
2. Try exploring [capabilities](https://github.com/novika-lang/novika/tree/rev10/src/novika/capabilities) and their [implementations](https://github.com/novika-lang/novika/tree/rev10/src/novika/capabilities/impl). This is where native code words like `dup` and `appendEcho` are defined. This is also a nice *starting point* to find bugs, optimize, add new stuff, etc. It's also one of the places where you can find typos, lack of documentation, and even some TODOs.
3. Try looking through the [interpreter code](https://github.com/novika-lang/novika/tree/rev10/src/novika) in general. I do have a compulsion to write comments, so most of the code is documented. How well documented is not for me to decide, but documented it is.
4. If you're someone who knows something about optimization, your eyes will hurt! Believe me :)

### What happens where?

When you do your `bin/novika hello.nk`, here's *roughly* the order in which various components get invoked:

1. [The command-line interface](https://github.com/novika-lang/novika/blob/rev10/src/cli.cr) frontend is what greets you (or doesn't) and sets everything up.
2. [Resolver](https://github.com/novika-lang/novika/blob/rev10/src/novika/resolver.cr) knows where everything is on the disk.
3. [Capability collection](https://github.com/novika-lang/novika/blob/rev10/src/novika/capability.cr) allows to control the capabilities of this particular invokation of the language/capabilities of the language overall. For example, this component is aware of you droping the `-Dnovika_console` flag.
4. [Capability interfaces and implementations](https://github.com/novika-lang/novika/tree/rev10/src/novika/capabilities) describe and implement those capabilities.
5. [Scissors](https://github.com/novika-lang/novika/blob/rev10/src/novika/scissors.cr) cut the contents of `hello.nk` (or any other blob of source code) into pieces called *unclassified forms*
6. [Classifier](https://github.com/novika-lang/novika/blob/rev10/src/novika/classifier.cr) classifies them, and shoves the resulting [forms](https://github.com/novika-lang/novika/tree/rev10/src/novika/forms) into a *file block*.
7. [Blocks](https://github.com/novika-lang/novika/blob/rev10/src/novika/forms/block.cr) are *the* most important forms in Novika.
7. [Engine](https://github.com/novika-lang/novika/blob/rev10/src/novika/engine.cr) [runs](https://github.com/novika-lang/novika/blob/db440e7f8ba4342a9eaacf77f76b6c59bc49528f/src/novika/engine.cr#L307) file blocks and all blocks "subordinate" to them. **This is the entrypoint for code execution, and one of the cornerstones of Novika**.
8. [Errors](https://github.com/novika-lang/novika/blob/rev10/src/novika/error.cr) happen. Or don't.

Note that most of these components interact with each other, making this list pretty pointless "for science".

### XXX: the hottest files in Novika

Hottest as in load and load as in performance, of course!

* Block [dictionary implementation](https://github.com/novika-lang/novika/blob/rev10/src/novika/dict.cr), `Dict`, is simply a wrapper around `Hash(K, V)`.
* Current [substrate implementation](https://github.com/novika-lang/novika/blob/rev10/src/novika/substrate.cr) is a *veerry* dumb copy-on-write array. Here's a helpful "formula": `block = ... + tape + dict + ...; tape = substrate + cursor`

### Stuff you might want to... borrow!

* A self-sufficient FFI [wrapper](https://github.com/novika-lang/novika/blob/rev10/src/novika/ffi.cr) only a few edits away!

### And the usual procedure...

1. Fork it (<https://github.com/novika-lang/novika/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

* [homonoidian](https://github.com/homonoidian) - creator and maintainer
