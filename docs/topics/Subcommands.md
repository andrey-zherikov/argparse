# Subcommands

Sophisticated command line tools, like `git`, have many subcommands (e.g., `git clone`, `git commit`, `git push`, etc.),
each with its own set of arguments. There are few ways how to use subcommands with `argparse`.

## `Subcommand` type

General approach to declare subcommands is to use `SubCommand` type. This type is behaving like a `SumType` from standard library
with few additions:
- It allows no command to be chosen.
- It supports at most one default subcommand (see [below](#default-subcommand) for details).

> See [SubCommand](SubCommand.md) section in the Reference for more detailed description of `SubCommand` type.
>
{style="note"}

<code-block src="code_snippets/subcommands.d" lang="c++"/>

## Subcommands with shared common arguments

In some cases command line tool has arguments that are common across all subcommands. They can be specified as regular
arguments in a struct that represents the whole program:

<code-block src="code_snippets/subcommands_common_args.d" lang="c++"/>

## Subcommand name and aliases

Using type name as a subcommand name in command line might not be convenient, moreover, the same subcommand might have
multiple names in command line (e.g. short and long versions). `Command` UDA can be used to list all acceptable names for
a subcommand:

<code-block src="code_snippets/subcommands_names.d" lang="c++"/>

## Default subcommand

Default subcommand is one that is selected when user does not specify any subcommand in the command line.
To mark a subcommand as default, use `Default` template:

<code-block src="code_snippets/subcommands_default.d" lang="c++"/>

## Enumerating subcommands in CLI mixin

One of the possible ways to use subcommands with `argparse` is to list all subcommands in `CLI` mixin. Although this might
be a useful feature, it is very limited: `CLI` mixin only allows overriding of the `main` function for this case:

<code-block src="code_snippets/subcommands_enumerate.d" lang="c++"/>
