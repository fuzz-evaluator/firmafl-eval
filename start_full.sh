#!/bin/bash

# This is a bash reimplementation of start_full.py.
# However, we do send the run_full.sh process to the background and bring it back
# to the foreground. This way, we can get the AFL output and do not run in
# shenanigans due to closed pipes

DIR="$(dirname "$(readlink -f "$0")")"

cd ${DIR}
./run_full.sh &
sleep 160
python test.py
wait
