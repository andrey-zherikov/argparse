# Arity

Sometimes an argument might accept more than one value. This is especially a case when a data member is an array or associative array.
In this case `argparse` supports two ways of specifying multiple values for an argument:
- `--arg value1 value2 ...`
- `--arg=value1,value2,...`
  > Note that `=` is a value of [`Config.assignChar`](Config.md#assignChar) and `,` is a value of [`Config.valueSep`](Config.md#valueSep)
  >
  {style="note"}


`argparse` supports these use cases for arity:
- Exact number of values.
- Limited range of minimum-maximum number of values.
- Unlimited range where only minimum number of values is provided (e.g. argument accepts _any number_ of values).

To adjust the arity, use one the following API:
- `NumberOfValues(size_t min, size_t max)` – sets both minimum and maximum number of values.
- `NumberOfValues(size_t num)` – sets the exact number of values.
- `MinNumberOfValues(size_t min)` – sets minimum number of values.
- `MaxNumberOfValues(size_t max)` – sets maximum number of values.

> Positional argument must have at least one value.
>
{style="warning"}

Example:

<code-block src="code_snippets/arity.d" lang="c++"/>

## Default arity

| Type                  |  Default arity  | Notes                                                                                                                       |
|-----------------------|:---------------:|-----------------------------------------------------------------------------------------------------------------------------|
| `bool`                |        0        | Boolean flags do not accept values with the only exception when they are specified in `--flag=true` format in command line. |
| String or scalar      |        1        | Exactly one value is accepted.                                                                                              |
| Static array          | Length of array | If a range is desired then use provided API to adjust arity.                                                                |
| Dynamic array         |  1 ... &#8734;  |                                                                                                                             |
| Associative array     |  1 ... &#8734;  |                                                                                                                             |
| `function ()`         |        0        | Same as boolean flag.                                                                                                       |
| `function (string)`   |        1        | Same as `string`.                                                                                                           |
| `function (string[])` |  1 ... &#8734;  | Same as `string[]` array.                                                                                                   |
| `function (RawParam)` |  1 ... &#8734;  | Same as `string[]` array.                                                                                                   |

## Named arguments with no values

Sometimes named arguments can have no values in command line. Here are two cases that arise in this situation:

- If value is optional and argument should get specific value in this case then use `AllowNoValue`.

- Argument must not have any values in command line. Use `RequireNoValue` in this case.

Both `AllowNoValue` and `RequireNoValue` accept a value that should be used when no value is provided in the command line.
The difference between them can be seen in this example:

<code-block src="code_snippets/arity_no_values.d" lang="c++"/>
