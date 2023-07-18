export NOVIKA_CWD=$(pwd)/cwd

$1 foo.nk
$1 ../foo.nk
$1 bar
$1 bar/baz.nk
$1 ../bar
$1 boo
$1 ../boo

export NOVIKA_CWD=$(pwd)/boo

$1
