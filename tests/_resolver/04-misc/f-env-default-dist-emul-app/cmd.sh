$1
$1 foo-app
$1 bar-app

o1=$($1 foo-app bar-app 2>&1)
if [ $? -ne 1 ]; then
  echo "$o1" >&2
  exit 1
fi
