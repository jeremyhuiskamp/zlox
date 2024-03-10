#!/usr/bin/env bash

fd -g '*.zig' src | entr zig build run