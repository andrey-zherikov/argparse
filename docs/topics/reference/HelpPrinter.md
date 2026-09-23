# HelpPrinter

`HelpPrinter` is the interface that `argparse` uses to render help text. An object implementing it is created by
[`Config.helpPrinterFactory`](Config.md#helpPrinterFactory) and is used everywhere help text is formatted: help
screen, [usage line printed on error](Config.md#helpOnError) and lists of arguments in error messages.

Where the text goes is decided when the object is created: the factory receives the sink to print to, so the functions
below don't take one.

It contains only the functions that `argparse` calls itself. Everything a help screen is built from is a part of
[`DefaultHelpPrinter`](DefaultHelpPrinter.md) and can be customized there, so in most cases the interface is not
implemented directly - deriving from `DefaultHelpPrinter` and overriding a few functions is enough.

## Public member functions

### printHelp

`printHelp` prints full help screen for the provided stack of (sub)commands.

**Signature**

```c++
void printHelp(const CommandHelpInfo[] commands)
```

**Parameters**

- `commands`

  Current stack of (sub)commands starting with top-level command. For example, if command line contains
  `tool subcmd1 subcmd2 -h` then `commands` contains `CommandHelpInfo` objects that correspond to `tool`, `subcmd1`
  and `subcmd2` commands respectively.

### printUsage

`printUsage` prints the usage line (`Usage: ...`) for the provided stack of (sub)commands. `argparse` calls it to print
the [usage line on error](Config.md#helpOnError).

**Signature**

```c++
void printUsage(const CommandHelpInfo[] commands)
```

**Parameters**

- `commands`

  Current stack of (sub)commands starting with top-level command, the same as for [`printHelp`](#printhelp). The usage
  line is printed for the last command in the stack.

### printArgumentList

`printArgumentList` prints the provided arguments rendered the way help screen shows them: name column and wrapped
description. `argparse` calls it to spell out which arguments an error message is about, so the text is printed to the
sink that the [factory](Config.md#helpPrinterFactory) was given and is then embedded into the message.

Every line, including the last one, is terminated with `\n`. Nothing is printed if `args` is empty.

**Signature**

```c++
void printArgumentList(const ArgumentHelpInfo[] args)
```

**Parameters**

- `args`

  Arguments to be listed.
