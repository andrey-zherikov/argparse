# Named arguments

_Named arguments_ (they are also called as flags or options) have one or more names. Each name can be short, long or both.
They can be declared using `NamedArgument` UDA which has the following parameters (see [reference](PositionalNamedArgument.md)
for details):

```c++
NamedArgument(string[] names...)
NamedArgument(string[] shortNames, string[] longNames)
```

| Name         | Type          | Optional/<br/>Required | Description                     |
|--------------|---------------|------------------------|---------------------------------|
| `name`       | `string[]...` | optional               | Name(s) of this argument.       |
| `shortNames` | `string[]`    | required               | Short name(s) of this argument. |
| `longNames`  | `string[]`    | required               | Long name(s) of this argument.  |

Example:

<code-block src="code_snippets/named_arguments.d" lang="c++"/>

## Short names

- _Short names_ in command line are those that start with short name prefix which is a single dash `-` by default (see
  [`Config.namedArgPrefix`](Config.md#namedArgPrefix) for customization).

If short names are not explicitly passed to `NamedArgument` UDA then all single-character names are considered short names
(see [reference](PositionalNamedArgument.md) for details).

> Note that short names can be longer than one character (they must be explicitly specified to `NamesArgument` UDA).
>
{style="note"}

The following usages of the argument short name in the command line are equivalent:
- `-name John`
- `-name=John`
- `-n John`
- `-n=John`

> Any other character can be used instead of `=` – see [`Config.assignChar`](Config.md#assignChar) for details.
>
{style="note"}

Additionally, for single-character short names the following is supported:
- Omitting of [assign character](Config.md#assignChar): `-nJohn` is an equivalent to `-n=John`.
- Arguments [bundling](Config.md#bundling): `-ab` is and equivalent to `-a -b`.

## Long names

_Long names_ in command line are those that start with long name prefix which is double dash `--` by default (see
[`Config.namedArgPrefix`](Config.md#namedArgPrefix) for customization).

If long names are not explicitly passed to `NamedArgument` UDA then all multi-character names are considered long names
(see [reference](PositionalNamedArgument.md) for details).

> Note that long names can be single-character (they must be explicitly specified to `NamesArgument` UDA).
>
{style="note"}

The following usages of the argument long names in the command line are equivalent:
- `--name John`
- `--name=John`
- `--n John`
- `--n=John`

> Any other character can be used instead of `=` – see [`Config.assignChar`](Config.md#assignChar) for details.
>
{style="note"}
