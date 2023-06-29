# Try to run app. Must load core only once
cd core
$1 foo

# Try to run core itself. Must load core only once
# because core loading is implicit
$1 .
