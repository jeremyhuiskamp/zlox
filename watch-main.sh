#!/usr/bin/env bash

# somehow entr doesn't detect `zig build run` exiting
# so we do it in two separate steps:
while : ; do
    zig build run
    build_status=$?
    
    # only wait for file changes if the build failed, otherwise we
    # were exiting the repl and probably want to try again immediately:
    if [ $build_status -ne 0 ]; then
        # -z: only run once
        # -p: don't run until a file changes
        fd -g '*.zig' src | entr -z -p echo "zig build run"
    fi
done