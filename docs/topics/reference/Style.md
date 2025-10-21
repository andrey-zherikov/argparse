# Style

`Style` struct contains style for error messages and help text. See [ANSI coloring and styling](ANSI-coloring-and-styling.md#styles-and-colors)
for all available styles and colors.

## Public members

### programName

Style for the program name. Default is `bold`.

### subcommandName

Style for the subcommand name. Default is `bold`.

### argumentGroupTitle

Style for the title of argument group. Default is `bold.underline`.

### argumentName

Style for the argument name. Default is `lightYellow`.

### namedArgumentValue

Style for the value of named argument. Default is `italic`.

### positionalArgumentValue

Style for the value of positional argument. Default is `lightYellow`.

### errorMessagePrefix

Style for *Error:* prefix in error messages. Default is `red`.

