# End of named arguments

When the command line contains an entry that is equal to [`Config.endOfNamedArgs`](Config.md#endOfNamedArgs)
(double dash `--` by default), `argparse` interprets all following command line entries as positional arguments, even
if they can match a named argument or a subcommand.

<code-block src="code_snippets/double_dash.d" lang="c++"/>
