# Calling the parser

`argparse` provides `CLI` template to call the parser covering different use cases. It has the following signatures:
- `template CLI(Config config, COMMAND)` – this is main template that provides multiple API (see below) for all
  supported use cases.
- `template CLI(Config config, COMMANDS...)` – convenience wrapper of the previous template that provides `main`
  template mixin only for the simplest use case with subcommands. See [Subcommands](Subcommands.md) section for details.
- `alias CLI(COMMANDS...) = CLI!(Config.init, COMMANDS)` – alias provided for convenience that allows using default
  `Config`, i.e., `config = Config.init`.

## Wrapper for `main` function

The recommended and most convenient way to use `argparse` is through `CLI!(...).main(alias newMain)` mixin template.
It declares the standard `main` function that parses command line arguments and calls provided `newMain` function with
an object that contains parsed arguments.

`newMain` function must satisfy these requirements:
- It must accept `COMMAND` type as a first parameter if `CLI` template is used with one `COMMAND`.
- It must accept all `COMMANDS` types as a first parameter if `CLI` template is used with multiple `COMMANDS...`.
  `argparse` uses `std.sumtype.match` for matching. Possible implementation of such `newMain` function would be a
  function that is overridden for every command type from `COMMANDS`. Another example would be a lambda that does
  compile-time checking of the type of the first parameter (see examples below for details).
- Optionally `newMain` function can take a `string[]` parameter as a second argument. Providing such a function will
  mean that `argparse` will parse known arguments only and all unknown ones will be passed into the second parameter of
  `newMain` function. If `newMain` function doesn’t have such parameter, then `argparse` will error out if there is an
  unknown argument provided in command line.
- Optionally `newMain` can return an `int`. In this case, this result will be returned from
  standard `main` function.

**Usage examples:**

<code-block src="code_snippets/call_parser1.d" lang="c++"/>

<code-block src="code_snippets/call_parser2.d" lang="c++"/>


## Low-level calling of parser

For the cases when providing `newMain` function is not possible or feasible, `parseArgs` function can accept a reference
to an object that receives the values of command line arguments:

`Result parseArgs(ref COMMAND receiver, string[] args)`

**Parameters:**

- `receiver` – object that is populated with parsed values.
- `args` – raw command line arguments (excluding `argv[0]` – first command line argument in `main` function).

**Return value:**

An object that can be cast to `bool` to check whether the parsing was successful or not.

> Note that this function will error out if command line contains unknown arguments.
>
{style="warning"}

**Usage example:**

<code-block src="code_snippets/call_parser4.d" lang="c++"/>


## Partial argument parsing

Sometimes a program may only parse a few of the command line arguments and process the remaining arguments in some different
way. In these cases, `CLI!(...).parseKnownArgs` function can be used. It works much like `CLI!(...).parseArgs` except
that it does not produce an error when unknown arguments are present. It has the following signatures:

- `Result parseKnownArgs(ref COMMAND receiver, string[] args, out string[] unrecognizedArgs)`

  **Parameters:**

    - `receiver` – the object that’s populated with parsed values.
    - `args` – raw command line arguments (excluding `argv[0]` – first command line argument in `main` function).
    - `unrecognizedArgs` – raw command line arguments that were not parsed.

  **Return value:**

  An object that can be cast to `bool` to check whether the parsing was successful or not.

- `Result parseKnownArgs(ref COMMAND receiver, ref string[] args)`

  **Parameters:**

    - `receiver` – the object that’s populated with parsed values.
    - `args` – raw command line arguments that are modified to have parsed arguments removed (excluding `argv[0]` – first
      command line argument in `main` function).

  **Return value:**

  An object that can be cast to `bool` to check whether the parsing was successful or not.

**Usage example:**

<code-block src="code_snippets/call_parser5.d" lang="c++"/>
