echo "$(pwd)/demo-cwd/foo,disk,1" > permissions

cd demo-cwd-sym

$1 -:abort-on-permission-request foo
