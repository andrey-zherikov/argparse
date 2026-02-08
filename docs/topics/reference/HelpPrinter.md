# HelpPrinter

`HelpPrinter` is a helper class that is used to create and print help screen.

## Public data members

### config

`HelpPrinter.config` holds a config object that was passed to constructor.

### style

`HelpPrinter.style` holds an actual style that should be applied to the help screen text. This should be used instead of `config.style`.

## Public member functions

### Constructor

Constructor of `HelpPrinter` initializes an object with specified `Config` and `Style` parameters.

**Signature**
```c++
this(const Config config, Style style)
```

> Note that `style` must contain actual style that should be applied to help screen. Usually it's either `config.style` or `Style.None`
> depending on run-time enablement ([environment](ANSI-coloring-and-styling.md#heuristic) or [command line option](ANSI-coloring-and-styling.md#enable/disable)).
>
{style="note"}


### formatCommandUsage

`formatCommandUsage` returns formatted string for command usage line which is usually `Usage: ...`.

**Signature**

```c++
string formatCommandUsage(string[] commandName, in CommandHelpInfo helpInfo)
```

**Parameters**

- `commandName`

  List of command names including names of parent commands starting with top-level command.

- `helpInfo`

  Help info about command.

**Return value**

String with formatted usage info.

### formatArgumentUsage

`formatArgumentUsage` returns formatted string for argument usage (argument representation in command usage line)
which is usually string like `[--foo FOO]`.

**Signature**

```c++
string formatArgumentUsage(in ArgumentHelpInfo helpInfo, bool usageString)
```

**Parameters**

- `helpInfo`

  Help info about argument.

- `usageString`

  If `true` then the returned value wil be used in usage string, otherwise in argument description.

**Return value**

String with formatted argument usage info.

### formatArgumentValue

`formatArgumentValue` returns formatted string for argument value: `--name <value>`. For example, it returns `[FOO ...]`
if argument usage is `--foo [FOO ...]`.

**Signature**

```c++
string formatArgumentValue(in ArgumentHelpInfo helpInfo)
```

**Parameters**

- `helpInfo`

  Help info about argument.

**Return value**

String with formatted argument value.

### createHelpScreen

This function creates [`HelpScreen`](HelpScreen.md) based on list of [commands](...HelpInfo.md#commandhelpinfo).

**Signature**

```c++
HelpScreen createHelpScreen(CommandHelpInfo[] commands)
```

**Parameters**

- `commands`

  Current stack of (sub)commands starting with top-level command.

**Return value**

`HelpScreen` object with all information about help screen.

### createSubCommandGroup

Function that creates a [`HelpScreen.Group`](HelpScreen.md#group) group from `CommandHelpInfo` data.

**Signature**

```c++
HelpScreen.Group createSubCommandGroup(const ref CommandHelpInfo cmd)
```

**Parameters**

- `cmd`

  Command that contains subcommands.

**Return value**

`HelpScreen.Group` object with subcommand entries.

### createArgumentsGroups

Function that creates an array of [`HelpScreen.Group`](HelpScreen.md#group) groups from commands data.
Usually this function merges groups with the same names from all commands.

**Signature**

```c++
HelpScreen.Group[] createArgumentsGroups(const ref CommandHelpInfo[] commands)
```

**Parameters**

- `commands`

  Current stack of (sub)commands starting with top-level command.

**Return value**

Array of `HelpScreen.Group` objects representing groups of arguments.

### printHelp

Function that creates help screen from commands info and prints through `sink`.

**Signature**

```c++
void printHelp(void delegate(string) sink, CommandHelpInfo[] commands)
```

**Parameters**

- `sink`

  Delegate that receives output in pieces.

- `commands`

  Current stack of (sub)commands starting with top-level command.


### printHelpScreen

This function prints [`HelpScreen`](HelpScreen.md) object through `sink`.

**Signature**

```c++
void printHelpScreen(void delegate(string) sink, const ref HelpScreen screen, size_t descriptionOffset)
```

**Parameters**

- `sink`

  Delegate that receives output in pieces.

- `screen`

  Help information to print.

- `descriptionOffset`

  Screen offset for parameter description. If help text can be represented as two columns of text, `descriptionOffset`
  is the position when the second column should start.

### printGroup

This function prints [`HelpScreen.Group`](HelpScreen.md#group) object through `sink`.

**Signature**

```c++
void printGroup(void delegate(string) sink, const ref HelpScreen.Group group, size_t descriptionOffset)
```

**Parameters**

- `sink`

  Delegate that receives output in pieces.

- `group`

  Group of parameters to print.

- `descriptionOffset`

  Screen offset for parameter description. If help text can be represented as two columns of text, `descriptionOffset`
  is the position when the second column should start.

### printParameter

This function prints [`HelpScreen.Parameter`](HelpScreen.md#parameter) object through `sink`.

**Signature**

```c++
  void printParameter(void delegate(string) sink, const ref HelpScreen.Parameter param, size_t descriptionOffset)
```

**Parameters**

- `sink`

  Delegate that receives output in pieces.

- `param`

  Parameter to print.

- `descriptionOffset`

  Screen offset for parameter description. If help text can be represented as two columns of text, `descriptionOffset`
  is the position when the second column should start.


## Public static functions

### wrapText

`wrapText` function wraps text into paragraphs by breaking it up into asequence of lines separated with `\n`, such that
the length of each line does not exceed specific limit. The last line is terminated with `\n`.

This function is similar to `std.string.wrap` but with few adjustments:
  - Styling, if any, is removed during calculation of word length.
  - Line breaks `\n` are preserved. This allows having line breaks where needed in addition to those that are added by function itself.
  - Output is returned via sink in parts rather than in allocated string. Caller can use `appender!string` if `string` is needed.

**Signature**

```c++
static void wrapText(void delegate(string) sink,
    string text,
    string firstIndent,
    string indent,
    size_t maxLineLength = 80)
```

**Parameters**

- `sink`

  Delegate that receives output in pieces.

- `text`

  Text to be wrapped.

- `firstIndent`

  String used to indent first line.

- `indent`

  String used to indent second and following lines.

- `maxLineLength`

  Maximum line length.

