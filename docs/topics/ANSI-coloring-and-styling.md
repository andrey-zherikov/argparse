# ANSI coloring and styling

Using colors in the command line tool’s output does not just look good: **contrasting** important elements like argument
names from the rest of the text **reduces the cognitive load** on the user. `argparse` uses [ANSI escape sequences](https://en.wikipedia.org/wiki/ANSI_escape_code)
to add coloring and styling to the error messages and help text. In addition, `argparse` offers public API to apply
colors and styles to any text printed to the console (see below).

> Coloring and styling API is provided in a separate `argparse.ansi` submodule. It has no dependencies on other parts of
> `argparse` so can be easily used in any other parts of a program unrelated to command line parsing.
>
{style="tip"}

<img src="default_styling.png" alt="Default styling" border-effect="rounded"/>

## Styles and colors

The following styles and colors are available in `argparse.ansi` submodule:

**Font styles:**
- `bold`
- `italic`
- `underline`

**Colors:**

| **Foreground** | **Background**   |
|----------------|------------------|
| `black`        | `onBlack`        |
| `red`          | `onRed`          |
| `green`        | `onGreen`        |
| `yellow`       | `onYellow`       |
| `blue`         | `onBlue`         |
| `magenta`      | `onMagenta`      |
| `cyan`         | `onCyan`         |
| `lightGray`    | `onLightGray`    |
| `darkGray`     | `onDarkGray`     |
| `lightRed`     | `onLightRed`     |
| `lightGreen`   | `onLightGreen`   |
| `lightYellow`  | `onLightYellow`  |
| `lightBlue`    | `onLightBlue`    |
| `lightMagenta` | `onLightMagenta` |
| `lightCyan`    | `onLightCyan`    |
| `white`        | `onWhite`        |

There is also a “virtual” style `noStyle` that means no styling is applied. It’s useful in ternary operations as a fallback
for the case when styling is disabled. See below example for details.

All styles above can be combined using `.` and even be used in regular output:

<code-block src="code_snippets/styling_helloworld.d" lang="c++"/>

The following example shows how styling can be used in custom help text (`Usage`, `Description`, `ShortDescription`, `Epilog` API):

<code-block src="code_snippets/styling_help.d" lang="c++"/>

Here is how help screen will look like:

<img src="styling_help.png" alt="Config help example" border-effect="rounded"/>


## Enable/disable the styling {id="enable/disable"}

By default `argparse` will try to detect whether ANSI styling is supported, and if so, it will apply styling to the help text and error messages.
Note that detection works for stdout and stderr separately so, for example, if stdout is redirected to a file (so stdout styling is disabled)
then stderr output (eg. error messages) will still have styling applied.

There is `Config.stylingMode` parameter that can be used to override default behavior:
- If it’s set to `Config.StylingMode.on`, then styling is **always enabled**.
- If it’s set to `Config.StylingMode.off`, then styling is **always disabled**.
- If it’s set to `Config.StylingMode.autodetect`, then [heuristics](#heuristic) are used to determine
  whether styling will be applied.

In some cases styling control should be exposed to a user as a command line argument (similar to `--color` argument in `ls` or `grep` command).
`argparse` supports this use case – just add an argument to a command (it can be customized with `@NamedArgument` UDA):

<code-block src="code_snippets/ansiStylingArgument.d" lang="c++"/>

This will add the following argument:

<img src="ansiStylingArgument.png" alt="ansiStylingArgument" border-effect="rounded"/>


## Heuristics for enabling styling {id="heuristic"}

Below is the exact sequence of steps `argparse` uses to determine whether or not to emit ANSI escape codes
(see detectSupport() function [here](https://github.com/andrey-zherikov/argparse/blob/master/source/argparse/ansi.d) for details):

1. If environment variable `NO_COLOR != ""`, then styling is **disabled**. See [here](https://no-color.org/) for details.
2. If environment variable `CLICOLOR_FORCE != "0"`, then styling is **enabled**. See [here](https://bixense.com/clicolors/) for details.
3. If environment variable `CLICOLOR == "0"`, then styling is **disabled**. See [here](https://bixense.com/clicolors/) for details.
4. If environment variable `ConEmuANSI == "OFF"`, then styling is **disabled**. See [here](https://conemu.github.io/en/AnsiEscapeCodes.html#Environment_variable) for details.
5. If environment variable `ConEmuANSI == "ON"`, then styling is **enabled**. See [here](https://conemu.github.io/en/AnsiEscapeCodes.html#Environment_variable) for details.
6. If environment variable `ANSICON` is defined (regardless of its value), then styling is **enabled**. See [here](https://github.com/adoxa/ansicon/blob/master/readme.txt) for details.
7. **Windows only** (`version(Windows)`):
    1. If environment variable `TERM` contains `"cygwin"` or starts with `"xterm"`, then styling is **enabled**.
    2. If `GetConsoleMode` call for `STD_OUTPUT_HANDLE`/`STD_ERROR_HANDLE` returns a mode that has `ENABLE_VIRTUAL_TERMINAL_PROCESSING` set, then styling is **enabled**.
    3. If `SetConsoleMode` call for `STD_OUTPUT_HANDLE`/`STD_ERROR_HANDLE` with `ENABLE_VIRTUAL_TERMINAL_PROCESSING` mode was successful, then styling is **enabled**.
8. **Posix only** (`version(Posix)`):
    1. If `STDOUT`/`STDERR` is **not** redirected (`isatty` returns 1), then styling is **enabled**.
9. If none of the above applies, then styling is **disabled**.
