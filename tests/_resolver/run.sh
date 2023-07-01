#!/bin/bash

root=$(pwd)/../../

for dir in ./[0-9]*/; do
  if [[ -d "$dir" ]]; then
    cd $dir
    echo "[[Running tests from: $dir]]"
    if [[ ! -f "baseline" ]]; then
      echo "error: no baseline file found, won't run"
      cd ..
      continue
    fi
    output=""
    for subdir in ./*/; do
      if [[ -d "$subdir" ]]; then
        cd $subdir
        echo "[Running test case $subdir]"
        if [[ -f "cmd.sh" ]]; then
          command_output=$(bash cmd.sh $root/bin/novika 2>&1)
        else
          command_output=$($root/bin/novika . 2>&1)
        fi
        if [[ $? -ne 0 ]]; then
          echo "$subdir: error: novika quit with non-zero exit code:"
          echo "$command_output" >&2
          cd ..
          continue
        fi
        output+=$(cat <(echo -ne "\n$subdir:\n$command_output"))
        cd ..
      fi
    done
    if ! diff -q <(echo "$output") "baseline"; then
      echo "$dir: error: some test case(s) failed"
      diff <(echo "$output") "baseline"
    fi
    cd ..
  fi
done

