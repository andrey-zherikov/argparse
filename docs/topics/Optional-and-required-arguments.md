# Optional and required arguments

Arguments can be marked as required or optional by adding `.Required` or `.Optional` to UDA. If required argument is
not present in command line, `argparse` will error out.

By default, _positional arguments_ are **required** and _named arguments_ are **optional**.

Example:

<code-block src="code_snippets/optional_required_arguments.d" lang="c++"/>
