# HelpPrinter

`HelpPrinter` is the interface that `argparse` uses to render help text.

It contains only the functions that `argparse` calls itself. Everything a help screen is built from is a part of
[`DefaultHelpPrinter`](DefaultHelpPrinter.md) and can be customized there, so in most cases the interface is not
implemented directly - deriving from `DefaultHelpPrinter` and overriding a few functions is enough.

## Public member functions

### printHelp

`printHelp` prints full help screen for the provided stack of (sub)commands.

**Signature**

```c++
void printHelp(void delegate(string) sink, CommandHelpInfo[] commands)
```

**Parameters**

- `sink`

  Delegate that is called with help text. `argparse` calls this delegate multiple times passing help text by pieces -
  as soon as they are formatted and ready to be printed. An implementation is free to ignore it and to send the text
  somewhere else.

- `commands`

  Current stack of (sub)commands starting with top-level command. For example, if command line contains
  `tool subcmd1 subcmd2 -h` then `commands` contains `CommandHelpInfo` objects that correspond to `tool`, `subcmd1`
  and `subcmd2` commands respectively.

### formatCommandUsage

`formatCommandUsage` returns the usage line (`Usage: ...`) for the last command in `commandName`.

**Signature**

```c++
string formatCommandUsage(string[] commandName, in CommandHelpInfo helpInfo)
```

### formatArgumentList

`formatArgumentList` returns the provided arguments rendered the way help screen shows them: name column and wrapped
description. It is used for error messages that have to spell out which arguments they are about.

**Signature**

```c++
string formatArgumentList(const ArgumentHelpInfo[] args)
```
