o1=$($1 foo 2>&1)
if [ $? -ne 1 ]; then
  echo "$o1" >&2
  exit 1
fi

o2=$($1 bar 2>&1)
if [ $? -ne 1 ]; then
  echo "$o2" >&2
  exit 1
fi

exit 0
