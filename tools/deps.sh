cat <<EOF | dot -Tpng > deps.png
digraph {
$(egrep -rw 'import +argparse' --include=*.d source | sed 's/public \+//; s/^source\/\(.\+\)\.d: *import \([^:; ]\+\).*/"\2" -> "\1"/; s/\//./g; s/\.package//g')
}
EOF