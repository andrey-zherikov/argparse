![Build](https://github.com/andrey-zherikov/argparse/actions/workflows/build.yaml/badge.svg)
[![codecov](https://codecov.io/gh/andrey-zherikov/argparse/branch/master/graph/badge.svg?token=H810TEZEHP)](https://codecov.io/gh/andrey-zherikov/argparse)

# Parser for command line arguments

`argparse` is a flexible utility for [D programming language](https://dlang.org/) to parse command line arguments.

> [!IMPORTANT]
> Please be aware that current HEAD contains breaking changes comparing to 1.* version.

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
