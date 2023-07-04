cd env
$1 ../foo.nk # outer foo

cd xyzzy
$1 ../foo.nk # inner foo

cd foozy
o2=$($1 ../foo.nk 2>&1) # doesn't exist (trying to break out of of the env)
if [ $? -ne 1 ]; then
  echo "$o2" >&2
  exit 1
fi

cd ../../..

o3=$($1 ../foo.nk 2>&1) # doesn't exist (trying to break out of of the env)
if [ $? -ne 1 ]; then
  echo "$o3" >&2
  exit 1
fi

cd booze/crazy-booze

o3=$($1 ../foo.nk 2>&1) # doesn't exist (trying to break out of of the env)
if [ $? -ne 1 ]; then
  echo "$o3" >&2
  exit 1
fi

exit 0
