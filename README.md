![Build](https://github.com/andrey-zherikov/argparse/actions/workflows/build.yaml/badge.svg)
[![codecov](https://codecov.io/gh/andrey-zherikov/argparse/branch/master/graph/badge.svg?token=H810TEZEHP)](https://codecov.io/gh/andrey-zherikov/argparse)

# Parser for command line arguments

`argparse` is a flexible utility for [D programming language](https://dlang.org/) to parse command line arguments.

> [!WARNING]
> :warning: Please be aware that current HEAD contains breaking changes comparing to 1.* 
> 
> :warning: This includes changes in documentation - documentation for 1.* version is [here](https://github.com/andrey-zherikov/argparse/blob/v1.3.0/README.md)

## Changes since 1.* version

<details>
<summary>Changelog</summary>

### Breaking changes

* Changes in `Config`:

  * Custom error handler function (`Config.errorHandler`) now receives message text with ANSI styling if styling is enabled. One can use `argparse.ansi.getUnstyledText` function to remove any styling - this function returns a range of unstyled `string` objects which can be used as is or `join`'ed into a string if  needed: `message.getUnstyledText.join`.

  * `Config.namedArgChar` is renamed to `Config.namedArgPrefix`.

  * `Config.endOfArgs` is renamed to `Config.endOfNamedArgs`.

  * `Config.helpStyle` is renamed to `Config.styling`.

  * `Config.addHelp` is renamed to `Config.addHelpArgument`.

* `Style.namedArgumentName` is renamed to `Style.argumentName`.

* Underlying type of `ansiStylingArgument` argument is changed. It can now be directly cast to boolean instead comparing against `Config.StylingMode`.

  So if you use it:
  ```d
    static auto color = ansiStylingArgument;
  ```
  then you should replace
  ```d
    if(args.color == Config.StylingMode.on)
  ```
  with
  ```d
    if(args.color)
  ```

* `@SubCommands` UDA is removed. One should use `SubCommand` template instead of `SumType`

  Simply replace
  ```d
    @SubCommands SumType!(CMD1, CMD2, Default!CMD3) cmd;
  ```
  with
  ```d
    SubCommand!(CMD1, CMD2, Default!CMD3) cmd;
  ```

* `@TrailingArguments` UDA is removed: all command line parameters that appear after double-dash `--` are considered as positional arguments. So if those parameters are to be parsed, use `@PositionalArgument` instead of `@TrailingArguments`.

* Functions for parsing customization (`PreValidation`, `Parse`, `Validation` and `Action`) now accept functions as runtime parameters instead of template arguments

  For example, replace this
  ```d
    .Parse     !((string s) { return cast(char) s[1]; })
    .Validation!((char v) { return v >= '0' && v <= '9'; })
  ```
  with
  ```d
    .Parse     ((string s) { return cast(char) s[1]; })
    .Validation((char v) { return v >= '0' && v <= '9'; })
  ```

* Dropped support for DMD-2.099.

### Enhancements and bug fixes

* Fix for `Command()` UDA: `ArrayIndexError` is not thrown anymore.
* Error messages are printed with `Config.styling` and now have the same styling as help text.
* New `errorMessagePrefix` member in `Config.styling` that determines the style of "Error:" prefix in error messages. This prefix is printed in red by default.
* New checks:
  * Argument is not allowed to be in multiple argument groups.
  * Subcommand name can't start with `Config.namedArgPrefix` (dash `-` by default).
* Functions for parsing customization (`PreValidation`, `Parse`, `Validation` and `Action`) can now return `Result` through `Result.Success` or `Result.Error` and provide error message if needed.
* Fixes for bundling of single-letter arguments.
  For example, the following cases are supported for `bool b; string s;` arguments:
  * `./prog -b -s=abc`
  * `./prog -b -s abc`
  * `./prog -b -sabc`
  * `./prog -bsabc`
  * `./prog -bs=abc`
* Removed support for delegate in `Config.errorHandler`, `Description`, `ShortDescription`, `Usage` and `Epilog` because of compiler's `closures are not yet supported in CTFE`.

### Other changes

* Removed dependency on `std.regex`.
* New code base: library implementation is almost fully rewritten (public API was not changed in this effort). Unnecessary templates were replaced with regular functions. As a result, compilation time and memory usage were improved: 2x better for `dub build` and 4x better for `dub test`.
* [New documentation](https://andrey-zherikov.github.io/argparse/)
</details>


## Features

- [Positional arguments](https://andrey-zherikov.github.io/argparse/positional-arguments.html):
    - Automatic type conversion of the value.
    - Required by default, can be marked as optional.
- [Named arguments](https://andrey-zherikov.github.io/argparse/named-arguments.html):
    - Multiple names are supported, including short (`-v`) and long (`--verbose`) ones.
    - [Case-sensitive/-insensitive parsing.](https://andrey-zherikov.github.io/argparse/config.html#caseSensitive)
    - [Bundling of short names](https://andrey-zherikov.github.io/argparse/arguments-bundling.html) (`-vvv` is same as `-v -v -v`).
    - [Equals sign is accepted](https://andrey-zherikov.github.io/argparse/config.html#assignChar) (`-v=debug`, `--verbose=debug`).
    - Automatic type conversion of the value.
    - Optional by default, can be marked as required.
- [Support different types of destination data member](https://andrey-zherikov.github.io/argparse/supported-types.html):
    - Scalar (e.g., `int`, `float`, `bool`).
    - String arguments.
    - Enum arguments.
    - Array arguments.
    - Hash (associative array) arguments.
    - Callbacks.
- [Different workflows are supported](https://andrey-zherikov.github.io/argparse/calling-the-parser.html):
    - Mixin to inject standard `main` function.
    - Parsing of known arguments only (returning not recognized ones).
    - Enforcing that there are no unknown arguments provided.
- [Shell completion](https://andrey-zherikov.github.io/argparse/shell-completion.html).
- [Options terminator](https://andrey-zherikov.github.io/argparse/end-of-named-arguments.html) (e.g., parsing up to `--` leaving any argument specified after it).
- [Arguments groups](https://andrey-zherikov.github.io/argparse/argument-dependencies.html).
- [Subcommands](https://andrey-zherikov.github.io/argparse/subcommands.html).
- [Fully customizable parsing](https://andrey-zherikov.github.io/argparse/parsing-customization.html):
    - Raw (`string`) data validation (i.e., before parsing).
    - Custom conversion of argument value (`string` -> any `destination type`).
    - Validation of parsed data (i.e., after conversion to `destination type`).
    - Custom action on parsed data (doing something different from storing the parsed value in a member of destination
      object).
- [ANSI colors and styles](https://andrey-zherikov.github.io/argparse/ansi-coloring-and-styling.html).
- [Built-in reporting of error happened during argument parsing](https://andrey-zherikov.github.io/argparse/config.html#errorHandler).
- [Built-in help generation](https://andrey-zherikov.github.io/argparse/help-generation.html).

## Documentation

Please find up-to-date documentation [here](https://andrey-zherikov.github.io/argparse/).
