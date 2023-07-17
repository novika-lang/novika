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
cd ../bar
$1 help core
$1 help ^core
$1 core/_xyzzy.nk
$1 ^core/_xyzzy.nk
