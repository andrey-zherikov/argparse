# Config

`argparse` provides decent amount of settings to customize the parser. All customizations can be done by creating
`Config` object with required settings (see below) and passing it to [CLI API](CLI-API.md).

## Assign character {id="assignChar"}

`Config.assignChar` is an assignment character used in arguments with value: `-a=5`, `-boo=foo`.

Default is equal sign `=`.

Example:

<code-block src="code_snippets/config_assignChar.d" lang="c++"/>

## Value separator {id="valueSep"}

`Config.valueSep` is a separator that is used to extract argument values: `-a=5,6,7`, `--boo=foo,far,zoo`.

Default is `,`.

Example:

<code-block src="code_snippets/config_valueSep.d" lang="c++"/>

## Named argument prefix {id="namedArgPrefix"}

`Config.namedArgPrefix` is a character that named arguments begin with.

Default is dash (`-`).

Example:

<code-block src="code_snippets/config_namedArgPrefix.d" lang="c++"/>

## End of named arguments {id="endOfNamedArgs"}

`Config.endOfNamedArgs` is a string that marks the end of all named arguments. All arguments that are specified
after this one are treated as positional regardless to the value which can start with `namedArgPrefix` (dash `-` by default)
or be a subcommand.

Default is double dash (`--`).

Example:

<code-block src="code_snippets/config_endOfNamedArgs.d" lang="c++"/>

## Case sensitivity {id="caseSensitive"}

`Config.caseSensitive` controls whether the argument names are case-sensitive. By default they are and it can be changed
by setting this member to `false`.

Default is `true`.

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
