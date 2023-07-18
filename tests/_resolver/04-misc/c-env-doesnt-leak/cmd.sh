o1=$($1 nested-env/bar 2>&1)
if [ $? -ne 1 ]; then
  echo "$o1" >&2
  exit 1
fi

$1 nested-env/bim
