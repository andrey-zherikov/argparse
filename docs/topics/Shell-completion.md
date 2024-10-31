# Shell completion

`argparse` supports tab completion of last argument for certain shells (see below). However, this support is limited
to the names of arguments and subcommands.

> Note that hidden arguments are not shown in shell completion. See [Hidden()](PositionalNamedArgument.md#hidden) for details.
>
{style="note"}
or returned in shell completion

## Wrappers for main function

If you are using `CLI!(...).main(alias newMain)` mixin template in your code then you can easily build a completer
(program that provides completion) by defining `argparse_completion` version (`-version=argparse_completion` option of
`dmd`). Don’t forget to use different output file for completer than your main program (`-of` option in `dmd`). No other
changes are necessary to generate completer, but you should consider minimizing the set of imported modules when
`argparse_completion` version is defined. For example, you can put all imports into your main function that is passed to
`CLI!(...).main(alias newMain)` – `newMain` parameter is not used in completer.

If you prefer having separate main module for completer, then you can use `CLI!(...).mainComplete` mixin template:
```c++
mixin CLI!(...).mainComplete;
```

In case if you prefer to have your own `main` function and would like to call completer by yourself, you can use
`int CLI!(...).complete(string[] args)` function. This function executes the completer by parsing provided `args` (note
that you should remove the first argument from `argv` passed to `main` function). The returned value is meant to be
returned from `main` function, having zero value in case of success.

## Low level completion

In case if none of the above methods is suitable, `argparse` provides `string[] CLI!(...).completeArgs(string[] args)`
function. It takes arguments that should be completed and returns all possible completions.

`completeArgs` function expects to receive all command line arguments (excluding `argv[0]` – first command line argument
in `main` function) in order to provide completions correctly (set of available arguments depends on subcommand). This
function supports two workflows:
- If the last argument in `args` is empty and it’s not supposed to be a value for a command line argument, then all
  available arguments and subcommands (if any) are returned.
- If the last argument in `args` is not empty and it’s not supposed to be a value for a command line argument, then only
  those arguments and subcommands (if any) are returned that start with the same text as the last argument in `args`.

For example, if there are `--foo`, `--bar` and `--baz` arguments available, then:
- Completion for `args=[""]` will be `["--foo", "--bar", "--baz"]`.
- Completion for `args=["--b"]` will be `["--bar", "--baz"]`.

## Using the completer

Completer that is provided by `argparse` supports the following shells:
- bash
- zsh
- tcsh
- fish

Its usage consists of two steps: completion setup and completing of the command line. Both are implemented as
subcommands (`init` and `complete` accordingly).

### Completion setup

Before using completion, completer should be added to the shell. This can be achieved by using `init` subcommand. It
accepts the following arguments (you can get them by running `<completer> init --help`):
- `--bash`: provide completion for bash.
- `--zsh`: provide completion for zsh. Note: zsh completion is done through bash completion so you should execute `bashcompinit` first.
- `--tcsh`: provide completion for tcsh.
- `--fish`: provide completion for fish.
- `--completerPath <path>`: path to completer. By default, the path to itself is used.
- `--commandName <name>`: command name that should be completed. By default, the first name of your main command is used.

Either `--bash`, `--zsh`, `--tcsh` or `--fish` is expected.

As a result, completer prints the script to setup completion for requested shell into standard output (`stdout`)
which should be executed. To make this more streamlined, you can execute the output inside the current shell or to do
this during shell initialization (e.g., in `.bashrc` for bash). To help doing so, completer also prints sourcing
recommendation to standard output as a comment.

Example of completer output for `<completer> init --bash --commandName mytool --completerPath /path/to/completer` arguments:
```bash
# Add this source command into .bashrc:
#       source <(/path/to/completer init --bash --commandName mytool)
complete -C 'eval /path/to/completer --bash -- $COMP_LINE ---' mytool
```

Recommended workflow is to install completer into a system according to your installation policy and update shell
initialization/config file to source the output of `init` command.

### Completing of the command line

Argument completion is done by `complete` subcommand (it’s default one). It accepts the following arguments (you can get them by running `<completer> complete --help`):
- `--bash`: provide completion for bash.
- `--tcsh`: provide completion for tcsh.
- `--fish`: provide completion for fish.

As a result, completer prints all available completions, one per line, assuming that it’s called according to the output
of `init` command.

