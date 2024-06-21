# Positional arguments

_Positional arguments_ are arguments that have specific position within the command line. This argument can be declared
using `PositionalArgument` UDA. It has the following parameters:

| # | Name          | Type     | Optional/<br/>Required | Description                                                                                                  |
|---|---------------|----------|------------------------|--------------------------------------------------------------------------------------------------------------|
| 1 | `position`    | `uint`   | required               | Zero-based unsigned position of the argument.                                                                |
| 2 | `placeholder` | `string` | optional               | Name of this argument that is shown in help text.<br/>If not provided, then the name of data member is used. |

Since that both _named_ and _positional arguments_ can be mixed in the command line, `argparse` enforces the following
restrictions to be able to parse a command line unambiguously:
- Positions of _positional arguments_ must be consecutive starting with zero without missing or repeating.
- _Positional argument_ must not have variable number of values except for the last argument.
- Optional _positional argument_ must have index greater than required _positional arguments_.
- If a command has default subcommand (see Subcommand section for details) the optional _positional argument_ is not
  allowed in this command.

Example:

<code-block src="code_snippets/positional_arguments.d" lang="c++"/>
