#!/usr/bin/env bash

fd -g '*.zig' | entr zig build test --summary all
