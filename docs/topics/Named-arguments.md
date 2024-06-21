# Named arguments

_Named arguments_ (they are also called as flags or options) have one or more name that can be separated into two categories:
- _Short names_ are those that start with single dash `-` (see [`Config.namedArgPrefix`](Config.md#namedArgPrefix) for customization).
- _Long names_ start with double dash `--` (see [`Config.namedArgPrefix`](Config.md#namedArgPrefix) for customization).

Both cases are fully supported with one caveat:
if a single-character argument is used with a double dash (e.g., `--n`) in command line, then it behaves the same as a
multi-character argument.

The following usages of the argument in the command line are equivalent:
- `--name John`
- `--name=John`
- `--n John`
- `--n=John`
- `-n John`
- `-n=John`
- `-nJohn` - this works for single-character names only

> Any other character can be used instead of `=` – see [`Config.assignChar`](Config.md#assignChar) for details.

_Named arguments_ can be declared using `NamedArgument` UDA which has the following parameters:

| # | Name   | Type                   | Optional/<br/>Required | Description                                                |
|---|--------|------------------------|------------------------|------------------------------------------------------------|
| 1 | `name` | `string` or `string[]` | optional               | Name(s) of this argument that can show up in command line. |

Example:

<code-block src="code_snippets/named_arguments.d" lang="c++"/>
