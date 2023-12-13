#!/usr/bin/env bash

set -euo pipefail
IFS=$'\t\n'
[[ $# -le 1 ]] || exit 2

{
    cd -- "${0%[/\\]*}/../source"

    echo 'digraph {'

    grep -rw 'import \+argparse' --include='*.d' | sed -E '
    s/^(.+)\.d: *(public +)?import +([^:; ]+).*/"\3" -> "\1"/
    s|/|.|g
    s/\.package//g
    ' | sort -u

    echo '}'
} | dot -Tsvg -o "${1-deps.svg}"
