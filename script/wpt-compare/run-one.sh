#!/usr/bin/env bash
# usage: run-one.sh <engine> <rel-path>   (WPT/TH env must be set)
timeout 12 node one.mjs "$1" "$2" 2>/dev/null || printf '%s\tHANG\n' "$2"
