# Novika: notes on raw looping performance

Let's loop 100 000 times (guess why not a million!) in Novika. Nothing simpler, right?

## Idiomatic

The idiomatic solution would be the following:

```novika
100_000 times: [ ]
```

On my machine, it runs for roughly 2 seconds (2000-2100ms).

Python, for reference: 

```python
for _ in range(100_000):
  pass
```

1.47ms (1400x faster; never thought I'd say that!)

**Now, however slow `times` is, I'd still recommend you to use it rather than any of the solutions below.** Novika will improve. Novika will become faster, `times` included; perhaps the observations made in this document will end up in core and you won't have to think about all this, then. Read and understand the following only if you are interested in ways to make things go faster in Novika. 

## While loop

`times:` uses `times`. The latter is implemented using a while loop (TODO: use `createDetachedLoop`). Performance impact of `times:` and `times` block opens is miniscule if any. We can say that the following code performs the same as the idiomatic solution.

```novika
0 $: i
while: [ i 100_000 < ]
[
  i 1 + =: i
]
```

That is, it also takes roughly 2 seconds (2000-2100ms).

## Infinite loop

The infinite loop `loop:`, having to execute two less blocks per iteration (`while` uses `createDetachedLoop`, which opens condition block followed by control block; the latter opens loop body block -- three blocks in total) runs about twice as fast:

```novika
0 $: i
loop: [
  i 100_000 >= => break
  i 1 + =: i
]
```

It takes about 1100-1300ms.

## Note for you, dear reader!

At this point, we leave the `break` and `next` land and venture into the land of *cursor jumping*.

Solutions below are acceptable when you need performance, but only in places where that *really* matters.

**Don't optimize because I didn't! I will, I promise!** You can tell me where the problem is, of course! I'd be glad to hear, really!

But if your framerate is 5 seconds, then surely, take a look at these.

## Standard solutions

Two kinds of solutions are possible at the lower-level: hybrid, and builtin-only (coreless).

### Hybrid

The code below shows roughly how loops are implemented in Novika under the hood.

```novika
0 $: index
this $: self

[ this $: body
  this |at "<HERE>"

  index 100_000 >= =>
    [ body endsAt |to ]

  index 1 + =: index
  this over |to
]

dup count this #endsAt rot pushes

open
```

Similar to `loop`, this runs in 1000-1100ms, and almost crosses the 1sec barrier.

#### Optimizing the hybrid solution

Optimization in Novika is mostly about *reducing the word count*, *reducing word lookup and block climbing*, and *using more builtins*.

1. A few low-hanging fruits: double `this`

```novika
0 $: index
this $: self

[ this dup $: body
  |at "<HERE>"

  index 100_000 >= =>
    [ body endsAt |to ]

  index 1 + =: index
  this over |to
]

dup count this #endsAt rot pushes

open
```


2. Replace `=>` with lower-level words:

```diff
0 $: index
this $: self

[ this dup $: body
  |at "<HERE>"

  index 100_000 >=
    [ ]
    [ body endsAt |to ]
  sel open

  index 1 + =: index
  this over |to
]

dup count this #endsAt rot pushes

open
```

3. Use stack for index:

```novika
0 $: index
this $: self

[ this dup $: body
  |at "<HERE>"

  index dup
    100_000 >=
      [ body endsAt |to ]
      [ ]
    sel open
  1 + =: index
  
  this over |to
]

dup count this #endsAt rot pushes

open
```

3. Define body in outer block (saving words/iter). This means `|at` always evaluates to 0 now, so let's replace it with 0. We'll have to use `stack swap hydrate!` though. We also save some time on block climbing.


```
0 $: index
this $: self

[ 0 "<HERE>"

  index dup
    100_000 >=
      [ body endsAt |to ]
      [ ]
    sel open
  1 + =: index

  body over |to
] dup $: body

dup count this #endsAt rot pushes

stack swap hydrate!
```

This hybrid solution is <1sec overall.

### Builtin-only

After finding a hybrid solution, let's try finding a builtin-only soltion to increase performance even more.

1. `>=` is not  a builtin, `=:` is not  a builtin. Let's try inlining/rewriting.

```
0 $: index
this $: self

[ 0 "<here>"

  index dup
    100_000 <
      [ ]
      [ body endsat |to ]
    sel open
  1 + self #index rot pushes

  body over |to
] dup $: body

dup count this #endsat rot pushes

stack swap hydrate!
```


This runs in 600-700ms, well below the 1sec barrier.

2. Keeping index on the stack, this time really.

```
0 $: index
this $: self

[ dup 100_000 <
    [ ]
    [ body endsAt |to ]
  sel open

  1 +

  body 0 |to
] dup $: body

dup count this #endsAt rot pushes

0 stack rot hydrate!
```

This runs in 200-300ms. I believe this is as far as you can go in Novika. To optimize this even further, I'll need to optimize the interpreter.

## Non-standard solutions

We can do some work ahead-of-time thanks to the fact that Novika is homoiconic. In our example, we can eliminate word lookup & block climbing entirely by substituting every word with its value form (e.g. word `dup` becomes the builtin `dup`). We can replace `block` and `endsAt` with the their values ahead-of-time as well. 

These manipulations are similar to what macros do, but at runtime rather than at earlier stages.

```novika
0 $: index
this $: self

"This is the block we are going to work on, our loop
 block. Note that '{block}' is simply a word; the curlies
 have no meaning at all, that is, they are parts of the
 word in the same way '-' is in 'hello-world'."

[ dup 100_000 <
    [ ]
    [ {block} {endsAt} |to ]
  sel stack swap hydrate!

  1 +

  {block} 0 |to
] $: block

"Dictionary for words we're going to 'replace'."
[
  block $: {block}
  block count $: {endsAt}
] obj $: dict

[
  ||-> [
    dup word?  => [ dict over entry:fetch? => nip  next ]
    dup block? => [ replaceFromDict  next ]
  ]
] @: replaceFromDict

block replaceFromDict $: body

0 stack body hydrate!
```

Such an approach obviously improves performance. Now the loop runs in 100-150ms. I believe this is the best Novika can do at the moment, considering how naive the interpreter code is. 120 milliseconds is 120 000 microseconds, which means an iteration takes about 1.2 microseconds. This is **a lot** considering how little gets done, but still, much better that the 2sec we had before.

