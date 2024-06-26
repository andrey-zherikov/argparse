# CLI API

`CLI` is a template that provides entry-point functions to call `argparse`.

Here are the signatures that `CLI` template has:
```c++
template CLI(Config config, COMMAND)
template CLI(Config config, COMMANDS...)
```

The second template with multiple `COMMANDS...` has only `main` function which wraps all `COMMANDS` inside internal
struct with only data member of type `SubCommand!COMMANDS` and calls `CLI(Config config, CMD).main` with that.

There is also an `alias` that uses default `Config.init` to simplify default behavior:
```c++
alias CLI(COMMANDS...) = CLI!(Config.init, COMMANDS);
```

## Public members

### parseKnownArgs

`CLI.parseKnownArgs` is a function that parses only known arguments from the command line.

All arguments that were not recognized during parsing are returned to a caller.

**Signature**

```c++
Result parseKnownArgs(ref COMMAND receiver, string[] args, out string[] unrecognizedArgs)
Result parseKnownArgs(ref COMMAND receiver, ref string[] args)
```

**Parameters**

- `receiver`

  Object that receives parsed command line arguments.

- `args`

  Command line arguments to parse (excluding `argv[0]` – first command line argument in `main` function).

- `unrecognizedArgs`

  Command line arguments that were not parsed.

**Notes**

- The second signature (without `unrecognizedArgs` parameter) returns not parsed arguments through `args` reference parameter.

**Return value**

`Result` object that can be cast to `bool` to check whether the parsing was successful or not.
Successful parsing for `parseKnownArgs` function means that there are no error during parsing of known arguments.
This means that having unrecognized arguments in a command line is not an error.

### parseArgs

`CLI.parseArgs` is a function that parses command line arguments and validates that there are no unknown ones.

**Signature**

```c++
Result parseArgs(ref COMMAND receiver, string[] args)
int parseArgs(alias newMain)(string[] args, COMMAND initialValue = COMMAND.init)
```

**Parameters**

- `receiver`

  Object that receives parsed command line arguments.

- `args`

  Command line arguments to parse (excluding `argv[0]` – first command line argument in `main` function).

- `newMain`

  Function that is called after successful command line parsing. See [`newMain`](#newMain) for details.

- `initialValue`

  Initial value for the object passed to `newMain` function.


**Notes**

- `newMain` will not be called in case of parsing error.

**Return value**

- In case of parsing error - `Result.exitCode` (`1` by default).
- In case of success:
  - `0` for the `parseArgs` version that doesn't accept `newMain` function.
  - `0` if `newMain` doesn't return a value that can be cast to `int`.
  - Value returned by `newMain` that is cast to `int`.

### complete

`CLI.complete` is a function that performs shell completion for command line arguments.

**Signature**

```c++
int complete()(string[] args)
```

**Parameters**

- `args`

  Command line arguments (excluding `argv[0]` – first command line argument in `main` function).

**Notes**

This function provides completion for the last argument in the command line:
- If the last entry in command line is an empty string (`""`) then it provides all available argument names prepended
  with [`Config.namedArgPrefix`](Config.md#namedArgPrefix).
- If the last entry in command line contains characters then `complete` provides completion only with those arguments
  that have names starting with specified characters.

**Return value**

- `0` in case of successful parsing.
- Non-zero otherwise.

### mainComplete

`CLI.mainComplete` is a mixin template that provides global `main` function which calls [`CLI.complete`](#complete).

**Signature**

```c++
template mainComplete()
```

**Notes**

Ingested `main` function is a simple wrapper of [`CLI.complete`](#complete) function that removes `argv[0]` from command line.

**Return value**

Value returned from [`CLI.complete`](#complete) function.

### main

`CLI.main` is a mixin template that does one of these:

- If `argparse_completion` version is defined then it instantiates `CLI.mainComplete` template mixin.
- Otherwise it provides global `main` function that calls [`CLI.parseArgs`](#parseargs) function.

**Signature**

```c++
template main(alias newMain)
```

**Parameters**

- `newMain`

  Function that is called after successful command line parsing. See [`newMain`](#newMain) for details.

**Notes**

- `newMain` parameter is not used in case if `argparse_completion` version is defined.

**Return value**

See [`CLI.mainComplete`](#maincomplete) and [`CLI.parseArgs`](#parseargs).

## newMain parameter {id="newMain"}

`newMain` parameter in `CLI` API is a substitution for classic `main` function with the following differences:
- Its first parameter has type of a command struct that is passed to `CLI` API. This parameter is filled with the data
  parsed from actual command line.

  `... newMain(COMMAND command)`

- It might have optional second parameter of type `string[]` that receives unknown command line arguments.

  `... newMain(COMMAND command, string[] unrecognizedArgs)`

- `newMain` can optionally return anything that can be cast to `int`. In this case, `argparse` will return that value from `CLI` API
  or from injected `main` function in case of `CLI.main`.

> If `newMain` has only one parameter, `argparse` will error out when command line contains unrecognized arguments.
>
{style="warning"}