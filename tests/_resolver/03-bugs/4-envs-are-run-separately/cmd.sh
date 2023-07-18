$1 .

# Run explicitly but without outer (yet will use outer's environment)
$1 env-defines/b.nk env-uses/a.nk

# Run explicitly with outer
$1 outer.nk env-defines/b.nk env-uses/a.nk
