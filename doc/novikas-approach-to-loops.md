# Novika's approach to loops

Loops are present in almost all programming languages; they make programming languages
Turing-complete, and so fun to work with. They drive web servers, operating systems,
interpreters such as Novika. Loops are the very heart of games and game programming.

This document is a brief, technical overview of how Novika approaches loops.

## Crystal

Novika is written in Crystal. Even though you won't find a "looping primitive" in kernel
or anywhere else, there still is a loop at the core of the interpreter which is accessible
from Novika-land: the *interpreter loop* itself. In rev10, the interpreter loop has its
own object -- a struct called `Engine`. You may see the interpreter loop being referred
to as the *engine loop* or the *exhaust loop*. These all stand for the same thing.

Here is what `Engine#exhaust` looks like, with error handling code omitted for it is in
this case irrelevant:

```crystal
until conts.empty?
  while form = block.next?
    form.opened(self)
  end
  conts.drop
end
```

We are interested in the implementation of `block.next?`, `Block#next?`:

```crystal=
def next? : Form?
  self.tape, _ = tape.next? || return
end
```

As you can see, it basically delegates the call to block's `Tape`. And since tape is passed
by value, we need to overwrite the block's ivar, `@tape`, to make the changes known (here via
the setter `tape=`).

We don't need to go deeper than `Tape#next?` though; its code shows us all we'd want
to know about `next?` that is not an implementation detail:

```crystal=
def next?
  {Tape.new(substrate, cursor + 1), substrate.at!(cursor)} if cursor < count
end
```

As you can see, first, the next (and resulting) tape is created that has its cursor advanced
once. Then, the item at the current cursor position is fetched from the tape substrate. This
makes the block's cursor slide to the right:

```text
[ | 1 2 3 ]
----------- starting to call .next?
[ 1 | 2 3 ]
[ 1 2 | 3 ]
[ 1 2 3 | ]
```

Actually, this is just what Novika's native `|slideRight` word does.

## Novika

Now let’s look at how Novika builds loops up from what’s described above.

### `repeat`

The basic looping primitive is called `repeat`. All it does is it sets the opener block's cursor
to 0. Therefore, after `repeat` is opened, `while form = block.next?` will start opening forms
at the beginning of the block again.

```novika
[ ahead 0 |to ] @: repeat
```

Note that no one forces you to use `repeat`. You could easily replace it in-place with `this 0 |to`.
Neither is it necessary to use `this` or `ahead`: you can apply `0 |to` to any block that is on the
continuations stack (to any block really, but to make it a loop and not just a block with cursor at 0
you'd want that block to be on the continuations stack).

That said, using `repeat` is a convention, mainly for hiding the underlying engine loop abuse.

Note that if `repeat` is reachable at all times, the loop will be infinite:

```novika
'To infinity and beyond!' echo repeat
```

You can think of `repeat` as a recursive call to the current block, but instead of growing the call
stack it replaces the pivot entry. In that it is similar to tail call. *Think of* is not *is* though,
beware. There are no tail calls anywhere.

**But not all is so simple.** There are two problems with `repeat`.

First, it doesn't re-instantiate the opener block. Same for `this 0 |at`, etc. `ahead eject` and friends
make their opener block dirty; that's one of the reasons we instantiate blocks upon opening in the first
place, and that's something we would want to hide from the final user for as long as possible and as
quickly as possible. If you open the same instance again, you may see a few forms missing (e.g., `$: foo`
will become just `$:`, because `$:` consumes (`ahead eject`s) the word that follows), or a few forms
which were not present in the prototype block.

Second, `repeat`, `this 0 |to`, etc. apply just to the current block, or to a block at a particular depth
only. E.g., you can't use them in a branch block to repeat the block that contains the branch; only the
branch block will be repeated. Either you'd need to exit earlier than you repeat, e.g., via `^`, or keep
a reference to the loop block and `0 |at` it when necessary.

### `loop`

The instantiation problem is solved by `loop`. Loop is the word you should use to make your loops. So
really, forget about `repeat`.

```novika
[ newWithBreakAndContinue $: block

  [ orphan block hydrate repeat ] open
] @: loop
```

For each iteration of the loop, a new empty stack is created by `orphan`. It is then packed together
with an instance of the iteration block into a continuation block by `hydrate`, and pushed onto the
continuations stack.

`orphan` takes care of creating a new empty block per each iteration, for the iteration stack.

`hydrate` takes care of creating an instance of iteration block per each iteration, for the iteration
block. Now, thanks to `loop`, the body block aka iteration block is instantiated as one would expect.

### Controlling `loop`s

Having an infinite loop is cool, but sometimes (almost always, actually) we need to stop looping,
or re-evaluate the loop body block.

#### Closing (breaking) a loop

One way to close a loop is to use `^`, but you'd have to make a little dance for that to work
properly, because you can also next the loop using `^`, or do nothing about the loop at all,
still with `^`.

`^` closes blocks all the way up to, and including, its *opener's parent*. In this code excerpt:

```novika
'Hey!' echo

[
  [
    'Aw!' echo
    ^
  ] loop
] open

'Bye!' echo
```

... the opener of `^` is the block `[ 'Aw!' echo ^ ]`. Its parent is the block `[ [ … ] loop ]`.
If we close it, we get to `[ 'Hey!' echo [ … ] open | 'Bye!' echo ]` (you can even see the `open`).

```text
Hey!
Aw!
Bye!
```

As you can see, the loop was closed successfully since `Aw!` was printed only once.

#### Continuing loops

To next a loop means to close the current iteration block, so the loop definition
(the one with `hydrate` and `repeat`, see above) can re-open it again. If you want to
use `^` for that, you'll need to have a nested block in `loop` and open `^` there:

```novika
[
  'A' echo
  [ ^ ] open
  'B' echo
] loop
```

... will print `A` for eternity.

#### How this looks in practice

If `[ ^ ]` continues body, then `=> [ ^ ]` continues the body too, i.e., you can *conditionally*
continue looping, and exit otherwise.

Here is a `loop` that will print numbers from 0 to 100.

```novika
0 $: n

[
  [
    n 100 < => [
      n echo
      n 1 + =: n
      ^ "(aka next)"
    ]
    ^ "(aka break)"
  ] loop
] open
```

We have to wrap it in `[ … ] open` because there's no block above the toplevel block, and so the
last `^` won't have any block to break out to and will crash the engine (because of continuations
stack underflow, if you're interested).

### Alternative control: implementing `break` and `next` for `loop`

Instead of torturing the user with `^` and its semantics and providing nothing but `loop`, Novika
implements call-depth-independent `break` and `next`, which are known by virtually all programmers
to do the following: `break` closes the loop that is its nearmost surrounding (aka deepest), and
`next` closes the loop iteration block of the loop that is its nearmost surrounding (aka deepest).

In order to implement these two words, `resume` comes very handy. It drops all continuations until
one that has the specified block as its continuation block. Here is how we could implement the
example above, now with the help of `resume`:

```novika
this $: blockToBreakTo
0 $: n

[
  ahead $: continueBlock

  n 100 < => [
    n echo
    n 1 + =: n
    continueBlock resume
  ]
  blockToBreakTo resume
] loop

'Bye!' echo
```

This piece of code still looks very weird, but it is just a small step toward `break` and `next`.
Thanks to `resume`, we can now set next-points programmatically.

#### `createLoop`

The next small step is `createLoop`. It takes an iteration body block and leaves three blocks: one
to start the loop, one to end the loop (to *break* it), and one to end current iteration (to *next* it).

```novika
[ $: iterBody

  #nil $: breakTo

 [ orphan iterBody hydrate repeat ] $: loopBody

 "Start loop:" [ this =: breakTo orphan loopBody hydrate! ]
 "Break loop:" [  breakTo resume ]
   "Continue:" [ loopBody resume ]
] @: createLoop
```

#### `loop`

Now it's easy to define `loop`, one that is much more user-friendly in terms of control.

```novika
[ new $: iterBody

  iterBody createLoop
    $: continueLoop
    $: breakLoop
    @: startLoop

  iterBody #break breakLoop opens
  iterBody #next continueLoop opens

  startLoop
] @: loop
```

This code creates a loop for an instance of the iteration body block it is given,
assigns the break and next handles `createLoop` leaves to the corresponding entries
in `iterBody`, and opens the `startLoop` handle. The latter starts looping immediately.

```novika
0 $: n

[
  n echo
  n 100 = => [ break ]
  n 1 + =: n
] loop
```

`next` also works. Let's write the famous fizz-buzz program:

```novika
1 $: n

[
  n 100 > => [ break ]

  n 15 /? => [ 'FizzBuzz' echo n 1 + =: n next ]
  n 5  /? => [     'Buzz' echo n 1 + =: n next ]
  n 3  /? => [     'Fizz' echo n 1 + =: n next ]

  n echo n 1 + =: n
] loop
```

Obviously there is some repetition that can be trivially eliminated, but this example is here
to demonstrate `next` and `break` (they could disappear if we start cleaning up the code).

#### `createDetachedLoop`

An important step towards having `while`, `until`, and more high-level looping constructs,
is `createDetachedLoop`, which defines `break` and `next` for a body block that is being
evaluated indirectly by a control block, and only if the condition block leaves a truthy
value on top of the stack it hydrated. `next` now resumes the control block instead of
the iteration body block.

```novika
[ $: ctrl $: cond new $: bodyInstance

  #nil $: ctrlNow

  [ cond val
      [ ctrl new =: ctrlNow
        bodyInstance enclose ctrlNow hydrate! ]
      breakLoop
    br
  ] createLoop drop $: breakLoop @: startLoop

  [
    bodyInstance #break breakLoop opens
    bodyInstance #next [ ctrlNow resume ] opens
    startLoop
  ]
] @: createDetachedLoop
```

#### `while`

Now that we have `createDetachedLoop`, we can implement `while`.

```novika
[ swap [ open ] createDetachedLoop open ] @: while
```

#### `until`

Until is the inverse of while (or while is the inverse of until). Here we just append
`not` to the condition. Since the condition block doesn't really expect anything to be
appended into it, we make a shallow copy of it.

```novika
[ <| shallowCopy #not << |> while ] @: until
```

#### `times`

`times` is the first high-level looping word Novika implements. It repeats the block
it is given a certain amount of times. We have previously made a loop which counts up.
Our sole purpose is to generalize that, and to expose `break` and `next` to the user's
body block. `createDetachedLoop` helps us do all of this.

```novika
[ swap $: max 0 $: n

  [ n max < ] [ n swap open n 1 + =: n ] createDetachedLoop open
] @: times
```

`break` and `next` are available to the body:

```novika
100 [
  dup 50 < => [ next ]
  dup 2 /? => [ next ]
  dup 80 > => [ break ]
  echo
] times
```

The code above outputs all odd numbers in the range `50 < n <= 80`:

```text
51
53
55
57
59
61
63
65
67
69
71
73
75
77
79
```

Novika also implements `times:`, which makes it look a bit more readable:

```
100 times: [
  dup 50 < => [ next ]
  dup 2 /? => [ next ]
  dup 80 > => [ break ]
  echo
]
```

#### `|slideRight`

`|slideRight` is easily implemented via `createDetachedLoop`. One difference from `times`
is that the maximum bound is the size of the block it's iterating over; it's dynamic and
must be recomputed every time.

```novika
[ $: body $: list

  body
  [ list dup |at over count < ]
  [ list dup |at 1 + |to
    list swap hydrate ]

  createDetachedLoop open
] @: |slideRight
```

#### `each`

`createDetachedLoop` can be used again. There is little point in using `each` when you have
`|slideRight`, but sometimes it may be preferred for purity or performance.

```
[ $: body $: list 0 $: index

  body
  [ index list count < ]
  [
     list index fromLeft enclose swap hydrate
     index 1 + =: index
  ] createDetachedLoop open
] @: each
```

#### And so on

This article ends here but Novika's high-level looping doesn't. Look into `core/block.nk`
for more looping vocabulary, like `collect`, `zipWithDefault`, and more. Most of them use
`createDetachedLoop` in one way or another, mainly to allow the user to `break` and `next`.

