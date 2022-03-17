![Build](https://github.com/andrey-zherikov/argparse/actions/workflows/build.yaml/badge.svg)
[![codecov](https://codecov.io/gh/andrey-zherikov/argparse/branch/master/graph/badge.svg?token=H810TEZEHP)](https://codecov.io/gh/andrey-zherikov/argparse)

# Parser for command-line arguments

`argparse` is a self-contained flexible utility to parse command line arguments that can work at compile-time.

**NOTICE: The API is not finalized yet so there might be backward incompatible changes until 1.0 version. Please refer
to [releases](https://github.com/andrey-zherikov/argparse/releases) for breaking changes.**

## Features

- Positional arguments:
    - Automatic type conversion of the value.
    - Required by default, can be marked as optional.
- Named arguments:
    - Multiple names are supported including short (`-v`) and long (`--verbose`) ones.
    - Case-sensitive/-insensitive parsing.
    - Bundling of short names (`-vvv` is same as `-v -v -v`).
    - Equals sign is accepted (`-v=debug`, `--verbose=debug`).
    - Automatic type conversion of the value.
    - Optional by default, can be marked as required.
- Support different types of destination data member:
    - Scalar (e.g. `int`, `float`, `bool`).
    - String arguments.
    - Enum arguments.
    - Array arguments.
    - Hash (associative array) arguments.
    - Callbacks.
- Parsing of known arguments only (returning not recognized ones).
- Options terminator (e.g. parsing up to `--` leaving any argument specified after it).
- Arguments groups.
- Subcommands.
- Fully customizable parsing:
    - Raw (`string`) data validation (i.e. before parsing).
    - Custom conversion of argument value (`string` -> any `destination type`).
    - Validation of parsed data (i.e. after conversion to `destination type`).
    - Custom action on parsed data (doing something different from storing the parsed value in a member of destination
      object).
- Built-in reporting of error happened during argument parsing.
- Built-in help generation

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
mixin Main.parseCLIArgs!(Basic, (args)
{
    // 'args' has 'Baisc' type
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
enum values = ([
  "--boolean",
  "--number","100",
  "--name","Jake",
  "--array","1","2","3",
  "--choice","foo",
  "--callback",
  "--callback1","cb-value",
  "--callback2","cb-v1","cb-v2",
].parseCLIArgs!Basic).get;

static assert(values.name     == "Jake");
static assert(values.unused   == Basic.init.unused);
static assert(values.number   == 100);
static assert(values.boolean  == true);
static assert(values.choice   == Basic.Enum.foo);
static assert(values.array    == [1,2,3]);
```

For more sophisticated CLI usage, `argparse` provides few UDAs:

```d
static struct Extended
{
    // Positional arguments are required by default
    @PositionalArgument(0)
    string name;

    // Named arguments can be attributed in bulk
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
mixin Main.parseCLIKnownArgs!(Extended, (args, unparsed)
{
    // 'args' has 'Extended' type
    static assert(is(typeof(args) == Extended));
    
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
    @NamedArgument  string a;
    @NamedArgument  string b;

    @TrailingArguments string[] args;
}

static assert(["-a","A","--","-b","B"].parseCLIArgs!T.get == T("A","",["-b","B"]));
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

static assert(["-b", "4"].parseCLIArgs!T.get == T("not set", 4));
```

### Limit the allowed values

In some cases an argument can receive one of the limited set of values so `AllowedValues` can be used here:

```d
struct T
{
    @(NamedArgument.AllowedValues!(["apple","pear","banana"]))
    string fruit;
}

static assert(["--fruit", "apple"].parseCLIArgs!T.get == T("apple"));
static assert(["--fruit", "kiwi"].parseCLIArgs!T.isNull);              // "kiwi" is not allowed
```

For the value that is not in the allowed list, this error will be printed:

```
Error: Invalid value 'kiwi' for argument '--fruit'.
Valid argument values are: apple,pear,banana
```

Note that if the type of destination variable is `enum` then the allowed values are automatically limited to those
listed in the `enum`.

## How to call the parser

### Wrappers for main function

The recommended and most convenient way to use `argparse` is through the `Main` wrapper. It provides the standard
`main` function that parses command line arguments and calls provided function with an object that contains parsed
arguments.

There are following mixins available:

- `Main.parseCLIArgs(TYPE, alias newMain, Config config = Config.init)` - parses arguments and ensures that there are no
  unknown arguments are provided.
- `Main.parseCLIKnownArgs(TYPE, alias newMain, Config config = Config.init)` - parses known arguments only.

**Usage examples:**

```d
struct T
{
    string a;
    string b;
}

mixin Main.parseCLIArgs!(T, (args)
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
struct T
{
    string a;
    string b;
}

mixin Main.parseCLIKnownArgs!(T, (args, unparsed)
{
    // 'args' has 'T' type
    static assert(is(typeof(args) == T));

    // unparsed arguments has 'string[]' type
    static assert(is(typeof(unparsed) == string[]));

    // do whatever you need
    import std.stdio: writeln;
    args.writeln;
    writeln("Unparsed args: ", unparsed);
    return 0;
});
```

### Complete argument parsing

There is a top-level function `parseCLIArgs` that parses the command line. It has the following signatures:

- `Result parseCLIArgs(T)(ref T receiver, string[] args, in Config config = Config.init)`

  **Parameters:**

    - `receiver` - the object that's populated with parsed values.
    - `args` - raw command line arguments.
    - `config` - settings that are used for parsing.

  **Return value:**

  An object that can be cast to `bool` to check whether the parsing was successful or not.

- `Nullable!T parseCLIArgs(T)(string[] args, in Config config = Config.init)`

  **Parameters:**

    - `args` - raw command line arguments.
    - `config` - settings that are used for parsing.

  **Return value:**

  If there is an error happened during the parsing then `null` is returned. Otherwise, an object of type `T` filled with
  values from the command line.

- `int parseCLIArgs(T, FUNC)(string[] args, FUNC func, in Config config = Config.init, T initialValue = T.init)`

  **Parameters:**

    - `args` - raw command line arguments.
    - `func` - function that's called with object of type `T` filled with data parsed from command line.
    - `config` - settings that are used for parsing.
    - `initialValue` - initial value for the object passed to `func`.

  **Return value:**

  If there is an error happened during the parsing then `int.max` is returned. In other case if
  `func` returns a value that can be cast to `int` then this value is returned. Otherwise, `0` is returned.

**Usage example:**

```d
struct T
{
    @NamedArgument string a;
    @NamedArgument string b;
}

enum result1 = parseCLIArgs!T([ "-a", "A", "-b", "B"]);
assert(result1.get == T("A","B"));
```

If you want to parse multiple command lines into single object then you can do this easily:

```d
T result2;
result2.parseCLIArgs([ "-a", "A" ]);
result2.parseCLIArgs([ "-b", "B" ]);
assert(result2 == T("A","B"));
```

You can even write your own `main` function that accepts

```d
int my_main(T command)
{
    // do something
    return 0;
}

int main(string[] args)
{
    return args.parseCLIArgs!T(&my_main);
}
```

### Partial argument parsing

Sometimes a program may only parse a few of the command-line arguments, passing the remaining arguments on to another
program. In these cases, `parseCLIKnownArgs` function can be used. It works much like `parseCLIArgs` except that it does
not produce an error when extra arguments are present. It has the following signatures:

- `Result parseCLIKnownArgs(T)(ref T receiver, string[] args, out string[] unrecognizedArgs, in Config config = Config.init)`

  **Parameters:**

    - `receiver` - the object that's populated with parsed values.
    - `args` - raw command line arguments.
    - `unrecognizedArgs` - raw command line arguments that were not parsed.
    - `config` - settings that are used for parsing.

  **Return value:**

  An object that can be cast to `bool` to check whether the parsing was successful or not.

- `Result parseCLIKnownArgs(T)(ref T receiver, ref string[] args, in Config config = Config.init)`

  **Parameters:**

    - `receiver` - the object that's populated with parsed values.
    - `args` - raw command line arguments that are modified to have parsed arguments removed.
    - `config` - settings that are used for parsing.

  **Return value:**

  An object that can be cast to `bool` to check whether the parsing was successful or not.

- `Nullable!T parseCLIKnownArgs(T)(ref string[] args, in Config config = Config.init)`

  **Parameters:**

    - `args` - raw command line arguments that are modified to have parsed arguments removed.
    - `config` - settings that are used for parsing.

  **Return value:**

  If there is an error happened during the parsing then `null` is returned. Otherwise, an object of type `T` filled with
  values from the command line.

- `int parseCLIKnownArgs(T, FUNC)(string[] args, FUNC func, in Config config = Config.init, T initialValue = T.init)`

  **Parameters:**

    - `args` - raw command line arguments.
    - `func` - function that's called with object of type `T` filled with data parsed from command line and the
      unrecognized arguments having the type of `string[]`.
    - `config` - settings that are used for parsing.
    - `initialValue` - initial value for the object passed to `func`.

  **Return value:**

  If there is an error happened during the parsing then `int.max` is returned. In other case if
  `func` returns a value that can be cast to `int` then this value is returned. Otherwise, `0` is returned.

**Usage example:**

```d
struct T
{
    @NamedArgument string a;
}

auto args = [ "-a", "A", "-c", "C" ];

assert(parseCLIKnownArgs!T(args).get == T("A"));
assert(args == ["-c", "C"]);
```

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
assert(parseCLIArgs!T(["-a","a"], (T t) {}) == 0);
assert(parseCLIArgs!T(["-b","b"], (T t) {}) == 0);
assert(parseCLIArgs!T([], (T t) {}) == 0);

// Both arguments are not allowed
assert(parseCLIArgs!T(["-a","a","-b","b"], (T t) { assert(false); }) != 0);
```

**Note that parenthesis are required in this UDA to work correctly.**

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
assert(parseCLIArgs!T(["-a","a","-b","b"], (T t) {}) == 0);
assert(parseCLIArgs!T([], (T t) {}) == 0);

// Only one argument is not allowed
assert(parseCLIArgs!T(["-a","a"], (T t) { assert(false); }) != 0);
assert(parseCLIArgs!T(["-b","b"], (T t) { assert(false); }) != 0);
```

**Note that parenthesis are required in this UDA to work correctly.**

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

parseCLIArgs!T(["-h"]);
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

static assert(["-b"]        .parseCLIArgs!T.get == T(true));
static assert(["-b","true"] .parseCLIArgs!T.get == T(true));
static assert(["-b","false"].parseCLIArgs!T.get == T(false));
static assert(["-b=true"]   .parseCLIArgs!T.get == T(true));
static assert(["-b=false"]  .parseCLIArgs!T.get == T(false));
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

static assert(["-i","-5","-u","8","-d","12.345"].parseCLIArgs!T.get == T(-5,8,12.345));
```

### String

`argparse` supports string arguments as pass trough:

```d
struct T
{
    @NamedArgument  string a;
}

static assert(["-a","foo"].parseCLIArgs!T.get == T("foo"));
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

static assert(["-a","apple"].parseCLIArgs!T.get == T(T.Fruit.apple));
static assert(["-a=pear"].parseCLIArgs!T.get == T(T.Fruit.pear));
```

### Counter

Counter argument is the parameter that tracks the number of times the argument occurred on the command line:

```d
struct T
{
    @(NamedArgument.Counter()) int a;
}

static assert(["-a","-a","-a"].parseCLIArgs!T.get == T(3));
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

static assert(["-a","1","2","3","-a","4","5"].parseCLIArgs!T.get.a == [1,2,3,4,5]);
static assert(["-b","1","2","3","-b","4","5"].parseCLIArgs!T.get.b == [[1,2,3],[4,5]]);
```

Alternatively you can set `Config.arraySep` to allow multiple elements in one parameter:

```d
struct T
{
    @NamedArgument int[] a;
}

Config cfg;
cfg.arraySep = ',';

assert(["-a","1,2,3","-a","4","5"].parseCLIArgs!T(cfg).get == T([1,2,3,4,5]));
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

assert(["-a","1","2","3","-b","4","5"].parseCLIArgs!T.get == T([1,2,3],[4,5]));
assert(["-a","1","-b","4","5"].parseCLIArgs!T.get == T([1],[4,5]));
```

### Associative array

If an argument is bound to an associative array, a string of the form "name=value" is expected as the next entry in
command line, or right within the option separated with an "=" sign:

```d
struct T
{
    @NamedArgument int[string] a;
}

static assert(["-a=foo=3","-a","boo=7"].parseCLIArgs!T.get.a == ["foo":3,"boo":7]);
```

Alternatively you can set `Config.arraySep` to allow multiple elements in one parameter:

```d
struct T
{
    @NamedArgument int[string] a;
}

Config cfg;
cfg.arraySep = ',';

assert(["-a=foo=3,boo=7"].parseCLIArgs!T(cfg).get.a == ["foo":3,"boo":7]);
assert(["-a","foo=3,boo=7"].parseCLIArgs!T(cfg).get.a == ["foo":3,"boo":7]);
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

static assert(["-a","-a","-a","-a"].parseCLIArgs!T.get.a == 4);
```

## Parsing customization

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

    assert(["-a"].parseCLIArgs!T.get.a == 10);       // use value from UDA
    assert(["-b"].parseCLIArgs!T.get.b == 20);       // use value from UDA
    assert(["-a", "30"].parseCLIArgs!T.get.a == 30); // providing value is allowed
    assert(["-b", "30"].parseCLIArgs!T.isNull);      // providing value is not allowed
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

    static assert(["-a","!4"].parseCLIArgs!T.get.a == 4);
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

assert(["-a","1,2,3","-a","4","5"].parseCLIArgs!T.get == T(["1,2,3","4","5"]));

Config cfg;
cfg.arraySep = ',';

assert(["-a","1,2,3","-a","4","5"].parseCLIArgs!T(cfg).get == T(["1","2","3","4","5"]));
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

       Add a -h/--help option to the parser.
       Defaults to true.

`Config.addHelp` - when it is set to `true` then `-h` and `--help` arguments are added to the parser. In case if the
command line has one of these arguments then the corresponding help text is printed and the parsing will be stopped.
If `parseCLIKnownArgs` or `parseCLIArgs` is called with function parameter then this callback will not be called.

Default is `true`.

### Error handling

`Config.errorHandler` - this is a handler function for all errors occurred during parsing the command line. It might be
either a function or a delegate that takes `string` parameter which would be an error message.

The default behavior is to print error message to `stderr`.

