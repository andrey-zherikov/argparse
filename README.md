![Build](https://github.com/andrey-zherikov/argparse/actions/workflows/build.yaml/badge.svg)
[![codecov](https://codecov.io/gh/andrey-zherikov/argparse/branch/master/graph/badge.svg?token=H810TEZEHP)](https://codecov.io/gh/andrey-zherikov/argparse)

# Parser for command-line arguments

`argparse` is a self-contained flexible utility to parse command line arguments that can work at compile-time.

**NOTICE: The API is not finalized yet so there might be backward incompatible changes until 1.0 version. Please refer
to [releases](https://github.com/andrey-zherikov/argparse/releases) for breaking changes.**

## Features

- [Positional arguments](#positional-arguments):
    - Automatic type conversion of the value.
    - Required by default, can be marked as optional.
- [Named arguments](#named-arguments):
    - Multiple names are supported including short (`-v`) and long (`--verbose`) ones.
    - [Case-sensitive/-insensitive parsing.](#case-sensitivity)
    - [Bundling of short names](#bundling-of-single-letter-arguments) (`-vvv` is same as `-v -v -v`).
    - [Equals sign is accepted](#assign-character) (`-v=debug`, `--verbose=debug`).
    - Automatic type conversion of the value.
    - Optional by default, can be marked as required.
- [Support different types of destination data member](#supported-types):
    - Scalar (e.g. `int`, `float`, `bool`).
    - String arguments.
    - Enum arguments.
    - Array arguments.
    - Hash (associative array) arguments.
    - Callbacks.
- [Different workflows are supported](#calling-the-parser):
    - Mixin to inject standard `main` function.
    - Parsing of known arguments only (returning not recognized ones).
    - Enforcing that there are no unknown arguments provided.
- [Shell completion](#shell-completion)
- [Options terminator](#trailing-arguments) (e.g. parsing up to `--` leaving any argument specified after it).
- [Arguments groups](#argument-dependencies).
- [Subcommands](#commands).
- [Fully customizable parsing](#argument-parsing-customization):
    - Raw (`string`) data validation (i.e. before parsing).
    - Custom conversion of argument value (`string` -> any `destination type`).
    - Validation of parsed data (i.e. after conversion to `destination type`).
    - Custom action on parsed data (doing something different from storing the parsed value in a member of destination
      object).
- [Built-in reporting of error happened during argument parsing](#error-handling).
- [Built-in help generation](#help-generation).


## Getting started

Here is the simple example showing the usage of `argparse` utility. It uses the basic approach when all members are
considered arguments with the same name as the name of member:

```d
import argparse;

static struct Basic
{
    // Basic data types are supported:
        // --name argument
        string name;
    
        // --number argument
        int number;
    
        // --boolean argument
        bool boolean;

    // Argument can have default value if it's not specified in command line
        // --unused argument
        string unused = "some default value";


    // Enums are also supported
        enum Enum { unset, foo, boo }
        // --choice argument
        Enum choice;

    // Use array to store multiple values
        // --array argument
        int[] array;

    // Callback with no args (flag)
        // --callback argument
        void callback() {}

    // Callback with single value
        // --callback1 argument
        void callback1(string value) { assert(value == "cb-value"); }

    // Callback with zero or more values
        // --callback2 argument
        void callback2(string[] value) { assert(value == ["cb-v1","cb-v2"]); }
}

// This mixin defines standard main function that parses command line and calls the provided function:
mixin CLI!Basic.main!((args)
{
    // 'args' has 'Basic' type
    static assert(is(typeof(args) == Basic));
  
    // do whatever you need
    import std.stdio: writeln;
    args.writeln;
    return 0;
});
```

If you run the program above with `-h` argument then you'll see the following output:

```
usage: hello_world [--name NAME] [--number NUMBER] [--boolean [BOOLEAN]] [--unused UNUSED] [--choice {unset,foo,boo}] [--array ARRAY ...] [--callback] [--callback1 CALLBACK1] [--callback2 [CALLBACK2 ...]] [-h]

Optional arguments:
  --name NAME
  --number NUMBER
  --boolean [BOOLEAN]
  --unused UNUSED
  --choice {unset,foo,boo}

  --array ARRAY ...
  --callback
  --callback1 CALLBACK1

  --callback2 [CALLBACK2 ...]

  -h, --help              Show this help message and exit
```

Parser can even work at compile time, so you can do something like this:

```d
enum values = {
    Basic values;
    assert(CLI!Basic.parseArgs(values,
        [
        "--boolean",
        "--number","100",
        "--name","Jake",
        "--array","1","2","3",
        "--choice","foo",
        "--callback",
        "--callback1","cb-value",
        "--callback2","cb-v1","cb-v2",
        ]));
    return values;
}();

static assert(values.name     == "Jake");
static assert(values.unused   == Basic.init.unused);
static assert(values.number   == 100);
static assert(values.boolean  == true);
static assert(values.choice   == Basic.Enum.foo);
static assert(values.array    == [1,2,3]);
```

For more sophisticated CLI usage, `argparse` provides few UDAs:

```d
static struct Advanced
{
    // Positional arguments are required by default
    @PositionalArgument(0)
    string name;

    // Named arguments can be attributed in bulk (parentheses can be omitted)
    @NamedArgument
    {
        string unused = "some default value";
        int number;
        bool boolean;
    }

    // Named argument can have custom or multiple names
        @NamedArgument("apple","appl")
        int apple;
    
        @NamedArgument(["b","banana","ban"])
        int banana;
}

// This mixin defines standard main function that parses command line and calls the provided function:
mixin CLI!Advanced.main!((args, unparsed)
{
    // 'args' has 'Advanced' type
    static assert(is(typeof(args) == Advanced));

    // unparsed arguments has 'string[]' type
    static assert(is(typeof(unparsed) == string[]));

    // do whatever you need
    import std.stdio: writeln;
    args.writeln;
    writeln("Unparsed args: ", unparsed);
    return 0;
});
```

If you run it with `-h` argument then you'll see the following:

```
usage: hello_world name [--unused UNUSED] [--number NUMBER] [--boolean [BOOLEAN]] [--apple APPLE] [-b BANANA] [-h]

Required arguments:
  name

Optional arguments:
  --unused UNUSED
  --number NUMBER
  --boolean [BOOLEAN]
  --apple APPLE
  -b BANANA, --banana BANANA, --ban BANANA

  -h, --help              Show this help message and exit
```


## Calling the parser

`argparse` provides `CLI` template to call the parser covering different use cases. It has the following signatures:
- `template CLI(Config config, COMMAND)` - this is main template that provides multiple API (see below) for all
  supported use cases.
- `template CLI(Config config, COMMANDS...)` - convenience wrapper of the previous template that provides `main`
  template mixin only for the simplest use case with subcommands. See corresponding [section](#commands) for details
  about subcommands.
- `alias CLI(COMMANDS...) = CLI!(Config.init, COMMANDS)` - alias provided for convenience that allows using default
  `Config`, i.e. `config = Config.init`.

### Wrapper for main function

The recommended and most convenient way to use `argparse` is through `CLI!(...).main(alias newMain)` mixin template.
It declares the standard `main` function that parses command line arguments and calls provided `newMain` function with
an object that contains parsed arguments.

`newMain` function must satisfy these requirements:
- It must accept `COMMAND` type as a first parameter if `CLI` template is used with one `COMMAND`.
- It must accept all `COMMANDS` types as a first parameter if `CLI` template is used with multiple `COMMANDS...`.
  `argparse` uses `std.sumtype.match` for matching. Possible implementation of such `newMain` function would be a
  function that is overridden for every command type from `COMMANDS`. Another example would be a lambda that does
  compile-time checking of the type of the first parameter (see examples for details).
- Optionally `newMain` function can take a `string[]` parameter as a second argument. Providing such a function will
  mean that `argparse` will parse known arguments only and all unknown ones will be passed as a second parameter to
  `newMain` function. If `newMain` function doesn't have such parameter then `argparse` will error out if the is an
  unknown argument provided in command line.
- Optionally `newMain` can return a result that can be cast to `int`. In this case, this result will be returned from
  standard `main` function.

**Usage examples:**

```d
struct T
{
    string a;
    string b;
}

mixin CLI!T.main!((args)
{
    // 'args' has 'T' type
    static assert(is(typeof(args) == T));

    // do whatever you need
    import std.stdio: writeln;
    args.writeln;
    return 0;
});
```

```d
struct cmd1
{
    string a;
}

struct cmd2
{
    string b;
}

mixin CLI!(cmd1, cmd2).main!((args, unparsed)
{
    // 'args' has either 'cmd1' or 'cmd2' type
    static if(is(typeof(args) == cmd1))
        writeln("cmd1: ", args);
    else static if(is(typeof(args) == cmd2))
        writeln("cmd2: ", args);
    else 
        static assert(false); // this would never happen
    
    // unparsed arguments has 'string[]' type
    static assert(is(typeof(unparsed) == string[]));

    return 0;
});
```

### Complete argument parsing

`CLI` template provides `parseArgs` function that parses the command line and ensures that there are no unknown
arguments specified in command line. It has the following signature:

`Result parseArgs(ref COMMAND receiver, string[] args))`

**Parameters:**

- `receiver` - the object that's populated with parsed values.
- `args` - raw command line arguments.

**Return value:**

An object that can be cast to `bool` to check whether the parsing was successful or not.

**Usage example:**

```d
struct T
{
    string a;
    string b;
}

assert(CLI!T.parseArgs!((T t) { assert(t == T("A","B")); })(["-a", "A", "-b", "B"]) == 0);
```


### Partial argument parsing

Sometimes a program may only parse a few of the command-line arguments, processing the remaining arguments in different
way. In these cases, `CLI!(...).parseKnownArgs` function can be used. It works much like `CLI!(...).parseArgs` except
that it does not produce an error when extra arguments are present. It has the following signatures:

- `Result parseKnownArgs(ref COMMAND receiver, string[] args, out string[] unrecognizedArgs)`

  **Parameters:**

  - `receiver` - the object that's populated with parsed values.
  - `args` - raw command line arguments.
  - `unrecognizedArgs` - raw command line arguments that were not parsed.

  **Return value:**

  An object that can be cast to `bool` to check whether the parsing was successful or not.

- `Result parseKnownArgs(ref COMMAND receiver, ref string[] args)`

  **Parameters:**

  - `receiver` - the object that's populated with parsed values.
  - `args` - raw command line arguments that are modified to have parsed arguments removed.

  **Return value:**

  An object that can be cast to `bool` to check whether the parsing was successful or not.

**Usage example:**

```d
struct T
{
    string a;
}

auto args = [ "-a", "A", "-c", "C" ];

T result;
assert(CLI!T.parseKnownArgs!(result, args));
assert(result == T("A"));
assert(args == ["-c", "C"]);
```


### Calling another `main` function after parsing

Sometimes it's useful to call some function with an object that has all command line arguments parsed. For this usage,
`argparse` provides `CLI!(...).parseArgs` template function that has the following signature:

`int parseArgs(alias newMain)(string[] args, COMMAND initialValue = COMMAND.init)`

**Parameters:**

- `newMain` - function that's called with object of type `COMMAND` as a first parmeter filled with the data parsed from
  command line; optionally it can take `string[]` as a second parameter which will contain unknown arguments
  (`parseKnownArgs` function will be used underneath in this case).
- `args` - raw command line arguments.
- `initialValue` - initial value for the object passed to `func`.

**Return value:**

If there is an error happened during the parsing then non-zero value is returned. If `newMain` function returns a
value that can be cast to `int` then this value is returned. Otherwise, `0` is returned.

**Usage example:**

```d
int my_main(T command)
{
    // do something
    return 0;
}

int main(string[] args)
{
    return CLI!T.parseArgs!my_main(args);
}
```

## Shell completion

`argparse` supports tab completion of last argument for certain shells (see below). However this support is limited to the names of arguments and
subcommands.

### Wrappers for main function

If you are using `CLI!(...).main(alias newMain)` mixin template in your code then you can easily build a completer
(program that provides completion) by defining `argparse_completion` version (`-version=argparse_completion` option of
`dmd`). Don't forget to use different file name for completer than your main program (`-of` option in `dmd`). No other
changes are necessary to generate completer but you should consider minimizing the set of imported modules when
`argparse_completion` version is defined. For example, you can put all imports into your main function that is passed to
`CLI!(...).main(alias newMain)` - `newMain` parameter is not used in completer.

If you prefer having separate main module for completer then you can use `CLI!(...).completeMain` mixin template:
```d
mixin CLI!(...).completeMain;
```

In case if you prefer to have your own `main` function and would like to call completer by yourself, you can use
`int CLI!(...).complete(string[] args)` function. This function executes the completer by parsing provided `args` (note
that you should remove the first argument from `argv` passed to `main` function). The returned value is meant to be
returned from `main` function having zero value in case of success.

### Low level completion

In case if none of the above methods is suitable, `argparse` provides `string[] CLI!(...).completeArgs(string[] args)`
function. It takes arguments that should be completed and returns all possible completions.

`completeArgs` function expects to receive all command line arguments (excluding `argv[0]` - first command line argument in `main`
function) in order to provide completions correctly (set of available arguments depends on subcommand). This function
supports two workflows:
- If the last argument in `args` is empty and it's not supposed to be a value for a command line argument, then all
  available arguments and subcommands (if any) are returned.
- If the last argument in `args` is not empty and it's not supposed to be a value for a command line argument, then only
  those arguments and subcommands (if any) are returned that starts with the same text as the last argument in `args`.

For example, if there are `--foo`, `--bar` and `--baz` arguments available, then:
- Completion for `args=[""]` will be `["--foo", "--bar", "--baz"]`.
- Completion for `args=["--b"]` will be `["--bar", "--baz"]`.

### Using the completer

Completer that is provided by `argparse` supports the following shells:
- bash
- zsh
- tcsh
- fish

Its usage consists of two steps: completion setup and completing of the command line. Both are implemented as
subcommands (`init` and `complete` accordingly).

#### Completion setup

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
this during shell initialization (e.g. in `.bashrc` for bash). To help doing so, completer also prints sourcing
recommendation to standard output as a comment.

Example of completer output for `<completer> init --bash --commandName mytool --completerPath /path/to/completer` arguments:
```
# Add this source command into .bashrc:
#       source <(/path/to/completer init --bash --commandName mytool)
complete -C 'eval /path/to/completer --bash -- $COMP_LINE ---' mytool
```

Recommended workflow is to install completer into a system according to your installation policy and update shell
initialization/config file to source the output of `init` command.

#### Completing of the command line

Argument completion is done by `complete` subcommand (it's default one). It accepts the following arguments (you can get them by running `<completer> complete --help`):
- `--bash`: provide completion for bash.
- `--tcsh`: provide completion for tcsh.
- `--fish`: provide completion for fish.

As a result, completer prints all available completions, one per line assuming that it's called according to the output
of `init` command.

## Argument declaration

### Positional arguments

Positional arguments are expected to be at a specific position within the command line. This argument can be declared
using `PositionalArgument` UDA:

```d
struct Params
{
    @PositionalArgument(0)
    string firstName;

    @PositionalArgument(0, "lastName")
    string arg;
}
```

Parameters of `PositionalArgument` UDA:

|#|Name|Type|Optional/<br/>Required|Description|
|---|---|---|---|---|
|1|`position`|`uint`|required|Zero-based unsigned position of the argument.|
|2|`name`|`string`|optional|Name of this argument that is shown in help text.<br/>If not provided then the name of data member is used.|

### Named arguments

As an opposite to positional there can be named arguments (they are also called as flags or options). They can be
declared using `NamedArgument` UDA:

```d
struct Params
{
    @NamedArgument
    string greeting;

    @NamedArgument(["name", "first-name", "n"])
    string name;

    @NamedArgument("family", "last-name")
    string family;
}
```

Parameters of `NamedArgument` UDA:

|#|Name|Type|Optional/<br/>Required|Description|
|---|---|---|---|---|
|1|`name`|`string` or `string[]`|optional|Name(s) of this argument that can show up in command line.|

Named arguments might have multiple names, so they should be specified either as an array of strings or as a list of
parameters in `NamedArgument` UDA. Argument names can be either single-letter (called as short options)
or multi-letter (called as long options). Both cases are fully supported with one caveat:
if a single-letter argument is used with a double-dash (e.g. `--n`) in command line then it behaves the same as a
multi-letter option. When an argument is used with a single dash then it is treated as a single-letter argument.

The following usages of the argument in the command line are equivalent:
`--name John`, `--name=John`, `--n John`, `--n=John`, `-nJohn`, `-n John`. Note that any other character can be used
instead of `=` - see [Parser customization](#parser-customization) for details.

### Trailing arguments

A lone double-dash terminates argument parsing by default. It is used to separate program arguments from other
parameters (e.g., arguments to be passed to another program). To store trailing arguments simply add a data member of
type `string[]` with `TrailingArguments` UDA:

```d
struct T
{
    string a;
    string b;

    @TrailingArguments string[] args;
}

assert(CLI!T.parseArgs!((T t) { assert(t == T("A","",["-b","B"])); })(["-a","A","--","-b","B"]) == 0);
```

Note that any other character sequence can be used instead of `--` - see [Parser customization](#parser-customization) for details.

### Optional and required arguments

Arguments can be marked as required or optional by adding `Required()` or `.Optional()` to UDA. If required argument is
not present parser will error out. Positional agruments are required by default.

```d
struct T
{
    @(PositionalArgument(0, "a").Optional())
    string a = "not set";

    @(NamedArgument.Required())
    int b;
}

assert(CLI!T.parseArgs!((T t) { assert(t == T("not set", 4)); })(["-b", "4"]) == 0);
```

### Limit the allowed values

In some cases an argument can receive one of the limited set of values so `AllowedValues` can be used here:

```d
struct T
{
    @(NamedArgument.AllowedValues!(["apple","pear","banana"]))
    string fruit;
}

assert(CLI!T.parseArgs!((T t) { assert(t == T("apple")); })(["--fruit", "apple"]) == 0);
assert(CLI!T.parseArgs!((T t) { assert(false); })(["--fruit", "kiwi"]) != 0);    // "kiwi" is not allowed
```

For the value that is not in the allowed list, this error will be printed:

```
Error: Invalid value 'kiwi' for argument '--fruit'.
Valid argument values are: apple,pear,banana
```

Note that if the type of destination variable is `enum` then the allowed values are automatically limited to those
listed in the `enum`.


## Argument dependencies

### Mutually exclusive arguments

Mutually exclusive arguments (i.e. those that can't be used together) can be declared using `MutuallyExclusive()` UDA:

```d
struct T
{
    @MutuallyExclusive()
    {
        string a;
        string b;
    }
}

// Either or no argument is allowed
assert(CLI!T.parseArgs!((T t) {})(["-a","a"]) == 0);
assert(CLI!T.parseArgs!((T t) {})(["-b","b"]) == 0);
assert(CLI!T.parseArgs!((T t) {})([]) == 0);

// Both arguments are not allowed
assert(CLI!T.parseArgs!((T t) { assert(false); })(["-a","a","-b","b"]) != 0);
```

**Note that parenthesis are required in this UDA to work correctly.**

Set of mutually exclusive arguments can be marked as required in order to require exactly one of the arguments:

```d
struct T
{
    @(MutuallyExclusive().Required())
    {
        string a;
        string b;
    }
}

// Either argument is allowed
assert(CLI!T.parseArgs!((T t) {})(["-a","a"]) == 0);
assert(CLI!T.parseArgs!((T t) {})(["-b","b"]) == 0);

// Both arguments or no argument is not allowed
assert(CLI!T.parseArgs!((T t) { assert(false); })([]) != 0);
assert(CLI!T.parseArgs!((T t) { assert(false); })(["-a","a","-b","b"]) != 0);
```

### Mutually required arguments

Mutually required arguments (i.e. those that require other arguments) can be declared using `RequiredTogether()` UDA:

```d
struct T
{
    @RequiredTogether()
    {
        string a;
        string b;
    }
}

// Both or no argument is allowed
assert(CLI!T.parseArgs!((T t) {})(["-a","a","-b","b"]) == 0);
assert(CLI!T.parseArgs!((T t) {})([]) == 0);

// Only one argument is not allowed
assert(CLI!T.parseArgs!((T t) { assert(false); })(["-a","a"]) != 0);
assert(CLI!T.parseArgs!((T t) { assert(false); })(["-b","b"]) != 0);
```

**Note that parenthesis are required in this UDA to work correctly.**

Set of mutually required arguments can be marked as required in order to require all arguments:

```d
struct T
{
    @(RequiredTogether().Required())
    {
        string a;
        string b;
    }
}

// Both arguments are allowed
assert(CLI!T.parseArgs!((T t) {})(["-a","a","-b","b"]) == 0);

// Single argument or no argument is not allowed
assert(CLI!T.parseArgs!((T t) { assert(false); })(["-a","a"]) != 0);
assert(CLI!T.parseArgs!((T t) { assert(false); })(["-b","b"]) != 0);
assert(CLI!T.parseArgs!((T t) { assert(false); })([]) != 0);
```

## Commands

Sophisticated command-line tools, like `git`, have many subcommands (e.g., `commit`, `push` etc.), each with its own set
of arguments. There are few ways to declare subcommands with `argparse`.

### Subcommands without UDA

All commands can be listed as template parameters to `Main.CLI`. Provided `main` function must be able to handle all
command types:

```d
struct sum
{
  int[] numbers;  // --numbers argument
}

struct min
{
  int[] numbers;  // --numbers argument
}

struct max
{
  int[] numbers;  // --numbers argument
}

int main_(max cmd)
{
  import std.algorithm: maxElement;

  writeln("max = ", cmd.numbers.maxElement);

  return 0;
}

int main_(min cmd)
{
  import std.algorithm: minElement;

  writeln("min = ", cmd.numbers.minElement);

  return 0;
}

int main_(sum cmd)
{
  import std.algorithm: sum;

  writeln("sum = ", cmd.numbers.sum);

  return 0;
}

// This mixin defines standard main function that parses command line and calls the provided function:
mixin CLI!(sum, min, max).main!main_;
```

### Subcommands with shared common arguments

In some cases command-line tool has arguments that are common across all subcommands. They can be specified as regular
arguments in a struct that represents the whole program. In this case subcommands must be listed as regular data member
having `SumType` type that contains types of all subcommands. The main function should accept a parameter for the
program, not for each subcommand:

```d
struct sum {}
struct min {}
struct max {}

struct Program
{
  int[] numbers;  // --numbers argument

  // SumType indicates sub-command
  // name of the command is the same as a name of the type
  SumType!(sum, min, max) cmd;
}

// This mixin defines standard main function that parses command line and calls the provided function:
mixin CLI!Program.main!((prog)
{
  static assert(is(typeof(prog) == Program));

  int result = prog.cmd.match!(
    (.max)
    {
      import std.algorithm: maxElement;
      return prog.numbers.maxElement;
    },
    (.min)
    {
      import std.algorithm: minElement;
      return prog.numbers.minElement;
    },
    (.sum)
    {
      import std.algorithm: sum;
      return prog.numbers.sum;
    }
  );

  writeln("result = ", result);

  return 0;
});
```

### Subcommand name and aliases

To define a command name that is not the same as the type that represents this command, one should use `Command` UDA -
it accepts a name and list of name aliases. All these names are recognized by the parser and are displayed in the help
text. For example:

```d
@(Command("maximum", "max")
.ShortDescription("Print the maximum")
)
struct MaxCmd
{
    int[] numbers;
}
```

Would result in this help fragment:

```
  maximum,max    Print the maximum
```

### Default subcommand

The default command is a command that is ran when user doesn't specify any command in the command line.
To mark a command as default, one should use `Default` template:

```d
SumType!(sum, min, Default!max) cmd;
```

## Help generation

### Command

`Command` UDA provides few customizations that affect help text. It can be used for top-level command and subcommands

- Program name (i.e. the name of top-level command) and subcommand name can be provided to `Command` UDA as a parameter. 
  If program name is not provided then `Runtime.args[0]` is used. If subcommand name is not provided then the name of
  the type that represents the command is used.
- `Usage` - allows custom usage text. By default, the parser calculates the usage message from the arguments it contains
  but this can be overridden with `Usage` call. If the custom text contains `%(PROG)` then it will be replaced by the
  command/program name.
- `Description` - used to provide a description of what the command/program does and how it works. In help messages, the
  description is displayed between the usage string and the list of the command arguments.
- `ShortDescription` - used to provide a brief description of what the command/program does. It is displayed in
  "Available commands" section on help screen of the parent command.
- `Epilog` - custom text that is printed after the list of the arguments.

### Argument

There are some customizations supported on argument level for both `PositionalArgument` and `NamedArgument` UDAs:

- `Description` - provides brief description of the argument. This text is printed next to the argument in the argument
  list section of a help message.
- `HideFromHelp` - can be used to indicate that the argument shouldn't be printed in help message.
- `Placeholder` - provides custom text that it used to indicate the value of the argument in help message.

### Example

Here is an example of how this customization can be used:

```d
@(Command("MYPROG")
 .Description("custom description")
 .Epilog("custom epilog")
)
struct T
{
  @NamedArgument  string s;
  @(NamedArgument.Placeholder("VALUE"))  string p;

  @(NamedArgument.HideFromHelp())  string hidden;

  enum Fruit { apple, pear };
  @(NamedArgument("f","fruit").Required().Description("This is a help text for fruit. Very very very very very very very very very very very very very very very very very very very long text")) Fruit f;

  @(NamedArgument.AllowedValues!([1,4,16,8])) int i;

  @(PositionalArgument(0).Description("This is a help text for param0. Very very very very very very very very very very very very very very very very very very very long text")) string param0;
  @(PositionalArgument(1).AllowedValues!(["q","a"])) string param1;

  @TrailingArguments string[] args;
}

CLI!T.parseArgs!((T t) {})(["-h"]);
```

This example will print the following help message:

```
usage: MYPROG [-s S] [-p VALUE] -f {apple,pear} [-i {1,4,16,8}] [-h] param0 {q,a}

custom description

Required arguments:
  -f {apple,pear}, --fruit {apple,pear}
                          This is a help text for fruit. Very very very very
                          very very very very very very very very very very
                          very very very very very long text
  param0                  This is a help text for param0. Very very very very
                          very very very very very very very very very very
                          very very very very very long text
  {q,a}

Optional arguments:
  -s S
  -p VALUE
  -i {1,4,16,8}
  -h, --help              Show this help message and exit

custom epilog
```

### Argument groups

By default, parser groups command-line arguments into “required arguments” and “optional arguments” when displaying help
message. When there is a better conceptual grouping of arguments than this default one, appropriate groups can be
created using `ArgumentGroup` UDA:

```d
struct T
{
    @(ArgumentGroup("group1").Description("group1 description"))
    {
        @NamedArgument
        {
            string a;
            string b;
        }
        @PositionalArgument(0) string p;
    }

    @(ArgumentGroup("group2").Description("group2 description"))
    @NamedArgument
    {
        string c;
        string d;
    }
    @PositionalArgument(1) string q;
}
```

When an argument is attributed with a group, the parser treats it just like a normal argument, but displays the argument
in a separate group for help messages:

```
usage: MYPROG [-a A] [-b B] [-c C] [-d D] [-h] p q

group1:
  group1 description

  -a A          
  -b B          
  p             

group2:
  group2 description

  -c C          
  -d D          

Required arguments:
  q             

Optional arguments:
  -h, --help    Show this help message and exit
```


## Supported types

### Boolean

Boolean types usually represent command line flags. `argparse` supports multiple ways of providing flag value:

```d
struct T
{
    @NamedArgument bool b;
}

assert(CLI!T.parseArgs!((T t) { assert(t == T(true)); })(["-b"]) == 0);
assert(CLI!T.parseArgs!((T t) { assert(t == T(true)); })(["-b","true"]) == 0);
assert(CLI!T.parseArgs!((T t) { assert(t == T(true)); })(["-b=true"]) == 0);
assert(CLI!T.parseArgs!((T t) { assert(t == T(false)); })(["-b","false"]) == 0);
assert(CLI!T.parseArgs!((T t) { assert(t == T(false)); })(["-b=false"]) == 0);
```

### Numeric

Numeric arguments are converted using `std.conv.to`:

```d
struct T
{
    @NamedArgument  int i;
    @NamedArgument  uint u;
    @NamedArgument  double d;
}

assert(CLI!T.parseArgs!((T t) { assert(t == T(-5,8,12.345)); })(["-i","-5","-u","8","-d","12.345"]) == 0);
```

### String

`argparse` supports string arguments as pass trough:

```d
struct T
{
    @NamedArgument  string a;
}

assert(CLI!T.parseArgs!((T t) { assert(t == T("foo")); })(["-a","foo"]) == 0);
```

### Enum

If an argument is bound to an enum, an enum symbol as a string is expected as a value, or right within the argument
separated with an "=" sign:

```d
struct T
{
    enum Fruit { apple, pear };

    @NamedArgument Fruit a;
}

assert(CLI!T.parseArgs!((T t) { assert(t == T(T.Fruit.apple)); })(["-a","apple"]) == 0);
assert(CLI!T.parseArgs!((T t) { assert(t == T(T.Fruit.pear)); })(["-a=pear"]) == 0);
```

### Counter

Counter argument is the parameter that tracks the number of times the argument occurred on the command line:

```d
struct T
{
    @(NamedArgument.Counter()) int a;
}

assert(CLI!T.parseArgs!((T t) { assert(t == T(3)); })(["-a","-a","-a"]) == 0);
```

### Array

If an argument is bound to 1D array, a new element is appended to this array each time the argument is provided in
command line. In case if an argument is bound to 2D array then new elements are grouped in a way as they appear in
command line and then each group is appended to this array:

```d
struct T
{
    @NamedArgument int[]   a;
    @NamedArgument int[][] b;
}

assert(CLI!T.parseArgs!((T t) { assert(t.a == [1,2,3,4,5]); })(["-a","1","2","3","-a","4","5"]) == 0);
assert(CLI!T.parseArgs!((T t) { assert(t.b == [[1,2,3],[4,5]]); })(["-b","1","2","3","-b","4","5"]) == 0);
```

Alternatively you can set `Config.arraySep` to allow multiple elements in one parameter:

```d
struct T
{
    @NamedArgument int[] a;
}

enum cfg = {
    Config cfg;
    cfg.arraySep = ',';
    return cfg;
}();

assert(CLI!(cfg, T).parseArgs!((T t) { assert(t == T([1,2,3,4,5])); })(["-a","1,2,3","-a","4","5"]) == 0);
```

#### Specifying number of values

In case the argument is bound to static array then the maximum number of values is set to the size of the array. For
dynamic array, the number of values is not limited. The minimum number of values is `1` in all cases. This behavior can
be customized by calling the following functions:

- `NumberOfValues(ulong min, ulong max)` - sets both minimum and maximum number of values.
- `NumberOfValues(ulong num)` - sets both minimum and maximum number of values to the same value.
- `MinNumberOfValues(ulong min)` - sets minimum number of values.
- `MaxNumberOfValues(ulong max)` - sets maximum number of values.

```d
struct T
{
  @(NamedArgument.NumberOfValues(1,3))
  int[] a;
  @(NamedArgument.NumberOfValues(2))
  int[] b;
}

assert(CLI!T.parseArgs!((T t) { assert(t == T([1,2,3],[4,5])); })(["-a","1","2","3","-b","4","5"]) == 0);
assert(CLI!T.parseArgs!((T t) { assert(t == T([1],[4,5])); })(["-a","1","-b","4","5"]) == 0);
```

### Associative array

If an argument is bound to an associative array, a string of the form "name=value" is expected as the next entry in
command line, or right within the option separated with an "=" sign:

```d
struct T
{
    @NamedArgument int[string] a;
}

assert(CLI!T.parseArgs!((T t) { assert(t == T(["foo":3,"boo":7])); })(["-a=foo=3","-a","boo=7"]) == 0);
```

Alternatively you can set `Config.arraySep` to allow multiple elements in one parameter:

```d
struct T
{
    @NamedArgument int[string] a;
}

enum cfg = {
    Config cfg;
    cfg.arraySep = ',';
    return cfg;
}();

assert(CLI!(cfg, T).parseArgs!((T t) { assert(t == T(["foo":3,"boo":7])); })(["-a=foo=3,boo=7"]) == 0);
assert(CLI!(cfg, T).parseArgs!((T t) { assert(t == T(["foo":3,"boo":7])); })(["-a","foo=3,boo=7"]) == 0);
```

In general, the keys and values can be of any parsable types.

### Callback

An argument can be bound to a function with one of the following signatures
(return value, if any, is ignored):

- `... function()`

  In this case, the argument is treated as a flag and the function is called every time when the argument is seen in
  command line.

- `... function(string)`

  In this case, the argument has exactly one value and the function is called every time when the argument is seen in
  command line and the value specified in command line is provided into `string` parameter.

- `... function(string[])`

  In this case, the argument has zero or more values and the function is called every time when the argument is seen in
  command line and the set of values specified in command line is provided into `string[]` parameter.

- `... function(RawParam)`

  In this case, the argument has one or more values and the function is called every time when the argument is seen in
  command line and the set of values specified in command line is provided into parameter.

```d
static struct T
{
    int a;

    @(NamedArgument("a")) void foo() { a++; }
}

assert(CLI!T.parseArgs!((T t) { assert(t == T(4)); })(["-a","-a","-a","-a"]) == 0);
```

## Argument parsing customization

Some time the functionality provided out of the box is not enough and it needs to be tuned.

Parsing of a command line string values into some typed `receiver` member consists of multiple steps:

- **Pre-validation** - argument values are validated as raw strings.
- **Parsing** - raw argument values are converted to a different type (usually the type of the receiver).
- **Validation** - converted value is validated.
- **Action** - depending on a type of the `receiver`, it might be either assignment of converted value to a `receiver`,
  appending value if `receiver` is an array or other operation.

In case if argument does not expect any value then the only one step is involved:

- **Action if no value** - similar to **Action** step above but without converted value.

If any of the steps fails then the command line parsing fails as well.

Each of the step above can be customized with UDA modifiers below. These modifiers take a function that might accept
either argument value(s) or `Param` struct that has these fields (there is also an alias, `RawParam`, where the type of
the `value` field is `string[]`):

- `config`- Config object that is passed to parsing function.
- `name` - Argument name that is specified in command line.
- `value` - Array of argument values that are provided in command line.

### Pre-validation

`PreValidation` modifier can be used to customize the validation of raw string values. It accepts a function with one of
the following signatures:

- `bool validate(string value)`
- `bool validate(string[] value)`
- `bool validate(RawParam param)`

The function should return `true` if validation passed and `false` otherwise.

### Parsing

`Parse` modifier allows providing custom conversion from raw string to typed value. It accepts a function with one of
the following signatures:

- `ParseType parse(string value)`
- `ParseType parse(string[] value)`
- `ParseType parse(RawParam param)`
- `bool parse(ref ParseType receiver, RawParam param)`
- `void parse(ref ParseType receiver, RawParam param)`

Parameters:

- `ParseType` is a type that the string value will be parsed to.
- `value`/`param` values to be parsed.
- `receiver` is an output variable for parsed value.

Parse function is supposed to parse values from `value`/`param` parameter into `ParseType` type and optionally return
boolean type indicating whether parsing was done successfully (`true`) or not (`false`).

### Validation

`Validation` modifier can be used to validate the parsed value. It accepts a function with one of the following
signatures:

- `bool validate(ParseType value)`
- `bool validate(ParseType[] value)`
- `bool validate(Param!ParseType param)`

Parameters:

- `value`/`param` has a value returned from `Parse` step.

The function should return `true` if validation passed and `false` otherwise.

### Action

`Action` modifier allows providing a custom logic of how `receiver` should be changed when argument has a value in
command line. It accepts a function with one of the following signatures:

- `bool action(ref T receiver, ParseType value)`
- `void action(ref T receiver, ParseType value)`
- `bool action(ref T receiver, Param!ParseType param)`
- `void action(ref T receiver, Param!ParseType param)`

Parameters:

- `receiver` is a receiver (destination field) which is supposed to be changed based on a `value`/`param`.
- `value`/`param` has a value returned from `Parse` step.

### Arguments with no values

Sometimes arguments are allowed to have no values in command line. Here are two cases that arise in this situation:

- Argument should get specific default value if there is no value provided in command line.
  `AllowNoValue` modifier should be used in this case.

- Argument must not have any values in command line. In this case `RequireNoValue` modifier should be used.

Both `AllowNoValue` and `RequireNoValue` modifiers accept a value that should be used when no value is provided in
command line. The difference between them can be seen in this example:

```d
struct T
{
    @(NamedArgument.AllowNoValue  !10) int a;
    @(NamedArgument.RequireNoValue!20) int b;
}

assert(CLI!T.parseArgs!((T t) { assert(t.a == 10); })(["-a"]) == 0);
assert(CLI!T.parseArgs!((T t) { assert(t.b == 20); })(["-b"]) == 0);
assert(CLI!T.parseArgs!((T t) { assert(t.a == 30); })(["-a","30"]) == 0);
assert(CLI!T.parseArgs!((T t) { assert(false); })(["-b","30"]) != 0);
```

### Usage example

All the above modifiers can be combined in any way:

```d
struct T
{
    @(NamedArgument
     .PreValidation!((string s) { return s.length > 1 && s[0] == '!'; })
     .Parse        !((string s) { return s[1]; })
     .Validation   !((char v) { return v >= '0' && v <= '9'; })
     .Action       !((ref int a, char v) { a = v - '0'; })
    )
    int a;
}

assert(CLI!T.parseArgs!((T t) { assert(t == T(4)); })(["-a","!4"]) == 0);
```

## Parser customization

`argparser` provides decent amount of settings to customize the parser. All customizations can be done by creating
`Config` object with required settings (see below).

### Assign character

`Config.assignChar` - the assignment character used in arguments with value: `-a=5`, `-b=foo`.

Default is equal sign `=`.

### Array separator

`Config.arraySep` - when set to `char.init`, value to array and associative array receivers are treated as an individual
value. That is, only one argument is appended inserted per appearance of the argument. If `arraySep` is set to something
else, then each value is first split by the separator, and the individual pieces are treated as values to the same
argument.

Default is `char.init`.

```d
struct T
{
    @NamedArgument string[] a;
}

assert(CLI!T.parseArgs!((T t) { assert(t == T(["1,2,3","4","5"])); })(["-a","1,2,3","-a","4","5"]) == 0);

enum cfg = {
    Config cfg;
    cfg.arraySep = ',';
    return cfg;
}();

assert(CLI!(cfg, T).parseArgs!((T t) { assert(t == T(["1","2","3","4","5"])); })(["-a","1,2,3","-a","4","5"]) == 0);
```

### Named argument character

`Config.namedArgChar` - the character that named arguments begin with.

Default is dash `-`.

### End of arguments

`Config.endOfArgs` - the string that conventionally marks the end of all arguments.

Default is double-dash `--`.

### Case sensitivity

`Config.caseSensitive` - by default argument names are case-sensitive. You can change that behavior by setting thia
member to `false`.

Default is `true`.

### Bundling of single-letter arguments

`Config.bundling` - when it is set to `true`, single-letter arguments can be bundled together, i.e. `-abc` is the same
as `-a -b -c`.

Default is `false`.

### Adding help generation

`Config.addHelp` - when it is set to `true` then `-h` and `--help` arguments are added to the parser. In case if the
command line has one of these arguments then the corresponding help text is printed and the parsing will be stopped.
If `CLI!(...).parseArgs(alias newMain)` or `CLI!(...).main(alias newMain)` is used then provided `newMain` function will
not be called.

Default is `true`.

### Error handling

`Config.errorHandler` - this is a handler function for all errors occurred during parsing the command line. It might be
either a function or a delegate that takes `string` parameter which would be an error message.

The default behavior is to print error message to `stderr`.

