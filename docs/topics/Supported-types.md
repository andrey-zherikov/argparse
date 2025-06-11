# Supported types

When command line entries are mapped to the annotated data members, the text value is converted to the type of the
data member.

## Boolean flags

Boolean types usually represent command line flags. `argparse` supports multiple ways of providing flag value including
negation (i.e., `--no-flag`):

| Command line entries           | Result    |
|--------------------------------|-----------|
| `-b` / `--boo`                 | `true`    |
| `-b=<value>` / `--boo=<value>` | `<value>` |
| `--no-b` / `--no-boo`          | `false`   |
| `-b <value>` / `--boo <value>` | error     |

> `<value>` is accepted only if it's provided with assignment `=` character ([`Config.assignChar`](Config.md#assignChar)),
> not as a separate command line entry.
>
{style="warning"}

`argparse` supports the following strings as a `<value>` (comparison is case-insensitive):

| `<value>`        | Result |
|------------------|--------|
| `true`,`yes`,`y` | true   |
| `false`,`no`,`n` | false  |

## Numbers and strings

Numeric (according to `std.traits.isNumeric`) and string (according to `std.traits.isSomeString`) data types are
seamlessly converted to destination type using `std.conv.to`:

<code-block src="code_snippets/types_number_string.d" lang="c++"/>

## Arrays

`argparse` supports 1D and 2D arrays:
- If an argument is bound to 1D array, a new element is appended to this array each time the argument is provided in
command line.
- In case of 2D array, new elements are grouped in a way as they appear in
command line and then each group is appended to this array.

The difference can be easily shown in the following example:

<code-block src="code_snippets/types_array.d" lang="c++"/>

## Associative arrays

`argparse` also supports associative array where simple value type (e.g. numbers, strings etc.). In this case, expected
format of the value is `key=value` (equal sign can be customized with [`Config.assignChar`](Config.md#assignChar)):

<code-block src="code_snippets/types_assoc_array.d" lang="c++"/>

## Enums {id="enum"}

It is encouraged to use `enum` types for arguments that have a limited set of valid values. In this case, `argparse`
validates that the value specified in command line matches one of enum identifiers:

<code-block src="code_snippets/types_enum.d" lang="c++"/>

In some cases the value for command line argument might have characters that are not allowed in enum identifiers.
Actual values that are allowed in command line can be adjusted with `AllowedValues` UDA:

<code-block src="code_snippets/types_enum_custom_values.d" lang="c++"/>

> When `AllowedValues` UDA is used, enum identifier is ignored so if argument is supposed to accept it, identifier
> must be listed in the UDA as well - see `"noapple"` in the example above.
>
{style="note"}

## Counter

Counter is an argument that tracks the number of times it's specified in the command line:

<code-block src="code_snippets/types_counter.d" lang="c++"/>

The same example with enabled [bundling](Arguments-bundling.md):

<code-block src="code_snippets/types_counter_bundling.d" lang="c++"/>

## Callback

If member type is a function, `argparse` will try to call it when the corresponding argument is specified in the
command line.

`argparse` supports the following function signatures (return value is ignored, if any):

- `... func()` - argument is treated as a boolean flag.

- `... func(string)` - argument has exactly one value. The value specified in command line is provided into `string` parameter.

- `... func(string[])` - argument has zero or more values. Values specified in command line are provided into `string[]` parameter.

- `... func(RawParam)` - argument has zero or more values. Values specified in command line are provided into parameter.

Example:

<code-block src="code_snippets/types_function.d" lang="c++"/>

## Custom types

`argparse` can actually work with any arbitrary type - just provide parsing function (see [Parsing customization](Parsing-customization.md#Parse)
for details):

<code-block src="code_snippets/types_custom.d" lang="c++"/>
