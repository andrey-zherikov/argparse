# Help generation


## Command

`Command` UDA provides few customizations that affect help text. It can be used for **top-level command** and **subcommands**.

- Program name (i.e., the name of top-level command) and subcommand name can be provided to `Command` UDA as a parameter.
  If program name is not provided, then `Runtime.args[0]` (a.k.a. `argv[0]` from `main` function) is used.
  If subcommand name is not provided (e.g., `@(Command.Description(...))`), then the name of the type that represents the command is used.
- `Usage` – allows custom usage text. By default, the parser calculates the usage message from the arguments it contains
  but this can be overridden with `Usage` call. If the custom text contains `%(PROG)` then it will be replaced by the
  command/program name.
- `Description` – used to provide a description of what the command/program does and how it works. In help messages, the
  description is displayed between the usage string and the list of the command arguments.
- `ShortDescription` – used to provide a brief description of what the subcommand does. It is applicable to subcommands
  only and is displayed in *Available commands* section on help screen of the parent command.
- `Epilog` – custom text that is printed after the list of the arguments.

`Usage`, `Description`, `ShortDescription` and `Epilog` modifiers take either `string` or `string function()`
value – the latter can be used to return a value that is not known at compile time.

## Argument

There are some customizations supported on argument level for both `PositionalArgument` and `NamedArgument` UDAs:

- `Description` – provides brief description of the argument. This text is printed next to the argument
  in the argument-list section of a help message. `Description` takes either `string` or `string function()`
  value – the latter can be used to return a value that is not known at compile time.
- `HideFromHelp` – can be used to indicate that the argument shouldn’t be printed in help message.
- `Placeholder` – provides custom text that is used to indicate the value of the argument in help message.

## Help text styling

`argparse` uses `Config.styling` to determine what style should be applied to different parts of the help text.
Please refer to [ANSI coloring and styling](ANSI-coloring-and-styling.md) section for details.

## Example

Here is an example of how this customization can be used:

<code-block src="code_snippets/help_example.d" lang="c++"/>

This example will print the following help message:

<img src="help_example1.png" alt="Help example" border-effect="rounded"/>

## Argument groups

By default, parser groups command line arguments into “required arguments” and “optional arguments” when displaying help
message. When there is a better conceptual grouping of arguments than this default one, appropriate groups can be
created using `ArgumentGroup` UDA.

This UDA has some customization for displaying help text:

- `Description` – provides brief description of the group. This text is printed right after group name.
  It takes either `string` or `string function()` value – the latter can be used to return a value that is not known
  at compile time.

Example:

<code-block src="code_snippets/help_argument_group.d" lang="c++"/>

When an argument is attributed with a group, the parser treats it just like a normal argument, but displays the argument
in a separate group for help messages:

<img src="help_argument_group.png" alt="Help argument group" border-effect="rounded"/>
