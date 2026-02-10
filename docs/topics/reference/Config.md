# Config

`argparse` provides decent amount of settings to customize the parser. All customizations can be done by creating
`Config` object with required settings (see below) and passing it to [CLI API](CLI-API.md).

## Assign character {id="assignChar"}

`Config.assignChar` is an assignment character used in arguments with value: `-a=5`, `-boo=foo`.

Default is equal sign `=`.

Example:

<code-block src="code_snippets/config_assignChar.d" lang="c++"/>


## Assign character {id="assignKeyValueChar"}

`Config.assignKeyValueChar` is an assignment character used in arguments that have associative array type: `-a=key=value`, `-boo=key=value`.

Default is equal sign `=`.

Example:

<code-block src="code_snippets/config_assignKeyValueChar.d" lang="c++"/>

## Value separator {id="valueSep"}

`Config.valueSep` is a separator that is used to extract argument values: `-a=5,6,7`, `--boo=foo,far,zoo`.

Default is `,`.

Example:

<code-block src="code_snippets/config_valueSep.d" lang="c++"/>

## Prefix for short argument name {id="shortNamePrefix"}

`Config.shortNamePrefix` is a string that short names of arguments begin with.

Default is dash (`-`).

Example:

<code-block src="code_snippets/config_namedArgPrefix.d" lang="c++"/>

## Prefix for long argument name {id="longNamePrefix"}

`Config.longNamePrefix` is a string that long names of arguments begin with.

Default is double dash (`--`).

Example:

<code-block src="code_snippets/config_namedArgPrefix.d" lang="c++"/>

## Variadic named arguments {id="variadicNamedArgument"}

`Config.variadicNamedArgument` flag controls whether named arguments should be follow [POSIX.1-2024](https://pubs.opengroup.org/onlinepubs/9799919799/)
guidelines which allows only one value per named argument: `-a value1 -a value2`.

Setting this flag to `true` allows multiple values to be passed to a named argument: `-a value1 value2`.

Default is `false`.

Example:

<code-block src="code_snippets/config_variadicNamedArgument.d" lang="c++"/>

## End of named arguments {id="endOfNamedArgs"}

`Config.endOfNamedArgs` is a string that marks the end of all named arguments. All arguments that are specified
after this one are treated as positional regardless to the value which can start with `Config.shortNamePrefix` or
`Config.longNamePrefix` or be a subcommand.

Default is double dash (`--`).

Example:

<code-block src="code_snippets/config_endOfNamedArgs.d" lang="c++"/>

## Case sensitivity {id="caseSensitive"}

`Config` type hase three data members to allow fine-grained tuning of case sensitivity:
- `Config.caseSensitiveShortName` to control case sensitivity for short argument names.
- `Config.caseSensitiveLongName` to control case sensitivity for long argument names.
- `Config.caseSensitiveSubCommand` to control case sensitivity for subcommands.

Default value for all of them is `true`.

> There is `Config.caseSensitive` helper function/property that sets all settings above to a specific value.
>
{style="note"}


Example:

<code-block src="code_snippets/config_caseSensitive.d" lang="c++"/>

## Bundling of single-character arguments {id="bundling"}

`Config.bundling` controls whether single-character arguments (usually boolean flags) can be bundled together.
If it is set to `true` then `-abc` is the same  as `-a -b -c`.

Default is `false`.

Example:

<code-block src="code_snippets/config_bundling.d" lang="c++"/>

## Adding help generation {id="addHelpArgument"}

`Config.addHelpArgument` can be used to add (if `true`) or not (if `false`) `-h`/`--help` argument.
In case if the command line has `-h` or `--help`, then the corresponding help text is printed and the parsing is stopped.
If `CLI!(...).parseArgs(alias newMain)` or `CLI!(...).main(alias newMain)` is used, then provided `newMain` function will
not be called.

Default is `true`.

Example:

<code-block src="code_snippets/config_addHelpArgument.d" lang="c++"/>

Help text from the first part of the example code above:

<img src="config_help.png" alt="Config help example" border-effect="rounded"/>


## Styling mode {id="stylingMode"}

`Config.stylingMode` controls whether styling for help text and errors should be enabled.
It has the following type: `enum StylingMode { autodetect, on, off }`:
- `Config.StylingMode.on`: styling is **always enabled**.
- `Config.StylingMode.off`: styling is **always disabled**.
- `Config.StylingMode.autodetect`: styling will be enabled when possible.

See [ANSI coloring and styling](ANSI-coloring-and-styling.md) for details.

Default value is `Config.StylingMode.autodetect`.

Example:

<code-block src="code_snippets/config_stylingMode.d" lang="c++"/>

Help text from the first part of the example code above:

<img src="config_stylingMode.png" alt="Config stylingMode example" border-effect="rounded"/>

## Styling scheme {id="styling"}

`Config.styling` contains style for the text output (error messages and help text). It has the following members:

- `programName`: style for the program name. Default is `bold`.
- `subcommandName`: style for the subcommand name. Default is `bold`.
- `argumentGroupTitle`: style for the title of argument group. Default is `bold.underline`.
- `argumentName`: style for the argument name. Default is `lightYellow`.
- `namedArgumentValue`: style for the value of named argument. Default is `italic`.
- `positionalArgumentValue`: style for the value of positional argument. Default is `lightYellow`.
- `errorMessagePrefix`: style for *Error:* prefix in error messages. Default is `red`.

See [ANSI coloring and styling](ANSI-coloring-and-styling.md) for details.

Example:

<code-block src="code_snippets/config_styling.d" lang="c++"/>

Help text from the first part of the example code above:

<img src="config_styling.png" alt="Config styling example" border-effect="rounded"/>

## Help printer {id="helpPrinter"}

`Config.helpPrinter` is a handler function to print help screen.
It receives the following parameters:
- `Config config` - config object that was provided to parsing API.
- `Style style` - style that should be applied to help screen.
- `CommandHelpInfo[] cmds` - current stack of (sub)commands starting with top-level command.
  For example, if command line contains `tool subcmd1 subcmd2 -h` then `cmd` will contain array of `CommandHelpInfo`
  objects that corresponds to `tool`, `subcmd1`, `subcmd2` commands respectively.

Example:

<code-block src="code_snippets/config_helpPrinter.d" lang="c++"/>


## Error handling {id="errorHandler"}

`Config.errorHandler` is a handler function for all errors occurred during command line parsing.
It is a function that receives `string` parameter which would contain an error message.

> Function must ne `nothrow`
>
{style="warning"}

The default behavior is to print error message to `stderr`.

Example:

<code-block src="code_snippets/config_errorHandler.d" lang="c++"/>

This code prints `Detected an error: Unrecognized arguments: ["-b"]` to `stderr`.

## Error exit code {id="errorExitCode"}

`Config.errorExitCode` holds and exit code in case of error.

Default value is `1`.
