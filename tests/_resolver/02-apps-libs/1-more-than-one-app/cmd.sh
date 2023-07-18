o1=$($1 a b 2>&1)
if [ $? -ne 1 ]; then
  echo "$o1" >&2
  exit 1
fi

o1=$($1 a b c 2>&1)
if [ $? -ne 1 ]; then
  echo "$o1" >&2
  exit 1
fi
