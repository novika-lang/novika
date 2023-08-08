if [ "$NORECUR" == "1" ]; then
  echo foo/a.nk
  echo
  echo bar/x.nk
  exit 0
fi

$1 -:dry-list +:dry-list-sm foo
$1 -:dry-list +:dry-list-sm bar
