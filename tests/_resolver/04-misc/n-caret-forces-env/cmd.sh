$1 foo
$1 help foo
$1 ^foo
$1 help ^foo
cd inner
$1 foo
$1 help foo
$1 ^foo
$1 help ^foo
$1 .
cd ../nested-env
$1 foo
$1 ^foo
$1 help ^foo
o1=$($1 ^../bar.nk 2>&1)
if [ $? -ne 1 ]; then
  echo "$o1" >&2
  exit 1
fi
cd ../bar
$1 help core
$1 help ^core
$1 core/_xyzzy.nk
$1 ^core/_xyzzy.nk
