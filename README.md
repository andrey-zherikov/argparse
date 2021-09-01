![Build](https://github.com/andrey-zherikov/argparse/actions/workflows/build.yaml/badge.svg)

# Parser for command-line arguments

`argparse` is a self-contained flexible utility to parse command line arguments that can work at compile-time.

**NOTICE: The API is not finalized yet so there might be backward incompatible changes until 1.0 version.
Please refer to [releases](https://github.com/andrey-zherikov/argparse/releases) for breaking changes.**  

## Getting started

Here is "Hello World" example showing the usage of this utility:

[//]: # (README_CONTENT_BEGIN file=examples/hello_world.d)
```d
import argparse;

struct Params
{
    // Positional arguments are required by default
    @PositionalArgument(0)
    string name;

    // Named argments are optional by default
    @NamedArgument("unused")
    string unused = "some default value";

    // Numeric types are converted automatically
    @NamedArgument("num")
    int number;

    // Boolean flags are supported
    @NamedArgument("flag")
    bool boolean;

    // Enums are also supported
    enum Enum { unset, foo, boo };
    @NamedArgument("enum")
    Enum enumValue;

    // Use array to store multiple values
    @NamedArgument("array")
    int[] array;

    // Callback with no args (flag)
    @NamedArgument("cb")
    void callback() {}

    // Callback with single value
    @NamedArgument("cb1")
    void callback1(string value) { assert(value == "cb-value"); }

    // Callback with zero or more values
    @NamedArgument("cb2")
    void callback2(string[] value) { assert(value == ["cb-v1","cb-v2"]); }
}

// Can even work at compile time
enum params = ([
    "--flag",
    "--num","100",
    "Jake",
    "--array","1","2","3",
    "--enum","foo",
    "--cb",
    "--cb1","cb-value",
    "--cb2","cb-v1","cb-v2",
    ].parseCLIArgs!Params).get;

static assert(params.name      == "Jake");
static assert(params.unused    == Params.init.unused);
static assert(params.number    == 100);
static assert(params.boolean   == true);
static assert(params.enumValue == Params.Enum.foo);
static assert(params.array     == [1,2,3]);
```
[//]: # (README_CONTENT_END)

## Features

- Positional arguments:
    - Automatic type conversion of the value.
    - Required by default, can be marked as optional.
- Named arguments:
    - Short and long names (`-v`, `--verbose`).
    - Multiple names are supported.
    - Case sensitive/insensitive parsing.
    - Bundling of short names (`-vvv` is same as `-v -v -v`).
    - Equals sign accepted (`-v=debug`, `--verbose=debug`).
    - Automatic type conversion of the value.
    - Optional by default, can be marked as required.
- User-defined conversion of argument value (`string` -> `destination type`).
- User-defined validation of argument value:
    - On raw (`string`) data (i.e. before parsing).
    - On parsed data (i.e. after parsing).
- Passing of known arguments only (returning not recognized ones).
- Options terminator (e.g. parsing up to `--` leaving any argument specified after it).
- Support different types of destination data member:
    - Scalar (e.g. `int`, `float`, `bool`).
    - String arguments.
    - Enum arguments.
    - Array arguments.
    - Hash (associative array) arguments.
    - Callbacks.
- Built-in reporting of error happened during argument parsing.

## Usage

### Calling the parser

There is a top-level function `parseCLIArgs(T)(string[] args, Config config)` that parses command line
specified in `args` parameter and returns `Nullable!T` which is `null` if there is an error happened
during parsing. Otherwise it returns object of type `T` filled with data from command line.

```d
struct T
{
    @NamedArgument("a") string a;
    @NamedArgument("b") string b;
}

enum result = parseCLIArgs!T([ "-a", "A", "-b", "B"]);

assert(result.get == T("A","B"));
```

If you want to reuse the parser and parse multiple command lines then you can do this easily:

```d
struct T
{
    @NamedArgument("a") string a;
    @NamedArgument("b") string b;
}

T result;
result.parseCLIArgs([ "-a", "A" ]);
result.parseCLIArgs([ "-b", "B" ]);

assert(result == T("A","B"));
```

#### Partial parsing

Sometimes a program may only parse a few of the command-line arguments, passing the remaining arguments on to another
program. In these cases, `parseCLIKnownArgs(T)(ref string[] args, Config config)` method can be used.
It works much like `parseCLIArgs()` except that it does not produce an error when extra arguments are present.
Instead, it removes parsed arguments from `args` parameter leaving remaining arguments.

```d
struct T
{
    @NamedArgument("a") string a;
    @NamedArgument("b") string b;
}

enum args = [ "-a", "A", "-c", "C" ];
enum result = parseCLIKnownArgs!T();

assert(result.get == T("A",""));
assert(args == ["-c", "C"]);
```


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

As an opposite to positional there can be named arguments (they are also called as flags or options).
They can be declared using `NamedArgument` UDA:

```d
struct Params
{
    @NamedArgument("greeting")
    string greeting;

    @NamedArgument(["name", "first-name", "n"])
    string name;
}
```

Parameters of `NamedArgument` UDA:

|#|Name|Type|Optional/<br/>Required|Description|
|---|---|---|---|---|
|1|`name`|`string` or `string[]`|required|Name(s) of this argument that can show up in command line.|

Named arguments might have multiple names, so they should be specified as an array of strings
in `NamedArgument` UDA. Argument names can be either single-letter (called as short options)
or multi-letter (called as long options). Both cases are fully supported with one caveat:
if a single-letter argument is used with a double-dash (e.g. `--n`) in command line then it
behaves the same as a multi-letter option. When an argument is used with a single dash then it is
treated as a single-letter argument.

The following usages of the argument in the command line are equivalent:
`--name John`, `--name=John`, `--n John`, `--n=John`, `-nJohn`, `-n John`.
Note that any other character can be used instead of `=` - see [Config](#Config) for details.

### Trailing arguments

A lone double-dash terminates argument parsing by default. It is used to separate program arguments
from other parameters (e.g., arguments to be passed to another program). To store trailing arguments
simply add a data member of type `string[]` with `TrailingArguments()` UDA:

```d
struct T
{
    @NamedArgument("a")  string a;
    @NamedArgument("b")  string b;

    @TrailingArguments() string[] args;
}

static assert(["-a","A","--","-b","B"].parseCLIArgs!T.get == T("A","",["-b","B"]));
```

Note that any other character sequence can be used instead of `--` - see [Config](#Config) for details.

### Optional and required arguments

Arguments can be marked as required or optional by adding `Required()` or `.Optional()` to UDA.
If required argument is not present parser will error out. Positional agruments are required by default.

```d
struct T
{
    @(PositionalArgument(0, "a").Optional())
    string a = "not set";

    @(NamedArgument("b").Required())
    int b;
}

static assert(["-b", "4"].parseCLIArgs!T.get == T("not set", 4));
```

## Supported types

### Boolean

Boolean types usually represent command line flags. `argparse` supports multiple ways of providing flag value:

```d
struct T
{
    @NamedArgument("b") bool b;
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
    @NamedArgument("i")  int i;
    @NamedArgument("u")  uint u;
    @NamedArgument("d")  double d;
}

static assert(["-i","-5","-u","8","-d","12.345"].parseCLIArgs!T.get == T(-5,8,12.345));
```

### String

`argparse` supports string arguments as pass trough:

```d
struct T
{
    @NamedArgument("a")  string a;
}

static assert(["-a","foo"].parseCLIArgs!T.get == T("foo"));
```

### Enum

If an argument is bound to an enum, an enum symbol as a string is expected as a value, or right
within the argument separated with an "=" sign:
    
```d
struct T
{
    enum Fruit { apple, pear };

    @(NamedArgument("a")) Fruit a;
}

static assert(["-a","apple"].parseCLIArgs!T.get == T(T.Fruit.apple));
static assert(["-a=pear"].parseCLIArgs!T.get == T(T.Fruit.pear));
```

### Counter

Counter argument is the parameter that tracks the number of times the argument occurred on the command line:

```d
struct T
{
    @(NamedArgument("a").Counter()) int a;
}

static assert(["-a","-a","-a"].parseCLIArgs!T.get == T(3));
```

### Array

If an argument is bound to 1D array, a new element is appended to this array each time the argument
is provided in command line. In case if an argument is bound to 2D array then new elements are
grouped in a way as they appear in command line and then each group is appended to this array:

```d
struct T
{
    @(NamedArgument("a")) int[]   a;
    @(NamedArgument("b")) int[][] b;
}

static assert(["-a","1","2","3","-a","4","5"].parseCLIArgs!T.get.a == [1,2,3,4,5]);
static assert(["-b","1","2","3","-b","4","5"].parseCLIArgs!T.get.b == [[1,2,3],[4,5]]);
```

Alternatively you can set `Config.arraySep` to allow multiple elements in one parameter:

```d
struct T
{
    @(NamedArgument("a")) int[] a;
}

Config cfg;
cfg.arraySep = ',';

assert(["-a","1,2,3","-a","4","5"].parseCLIArgs!T(cfg).get == T([1,2,3,4,5]));
```

### Associative array

If an argument is bound to an associative array, a string of the form "name=value" is expected as
the next entry in command line, or right within the option separated with an "=" sign:

```d
struct T
{
    @(NamedArgument("a")) int[string] a;
}

static assert(["-a=foo=3","-a","boo=7"].parseCLIArgs!T.get.a == ["foo":3,"boo":7]);
```

Alternatively you can set `Config.arraySep` to allow multiple elements in one parameter:

```d
struct T
{
    @(NamedArgument("a")) int[string] a;
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

  In this case, the argument is treated as a flag and the function is called every time when
  the argument is seen in command line.

- `... function(string)`

  In this case, the argument has exactly one value and the function is called every time when
  the argument is seen in command line and the value specified in command line is provided into `string` parameter.

- `... function(string[])`

  In this case, the argument has zero or more values and the function is called every time when
  the argument is seen in command line and the set of values specified in command line is provided into `string[]` parameter.

- `... function(RawParam)`

  In this case, the argument has one or more values and the function is called every time when
  the argument is seen in command line and the set of values specified in command line is provided into parameter.

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
- **Action** - depending on a type of the `receiver`, it might be either assignment of converted value
  to a `receiver`, appending value if `receiver` is an array or other operation.

In case if argument does not expect any value then the only one step is involved:
- **Action if no value** - similar to **Action** step above but without converted value.

If any of the steps fails then the command line parsing fails as well.

Each of the step above can be customized with UDA modifiers below. These modifiers take a function
that might accept either argument value(s) or `Param` struct that has these fields (there is also
an alias, `RawParam`, where the type of the `value` field is `string[]`):
- `config`- Config object that is passed to parsing function.
- `name` - Argument name that is specified in command line.
- `value` - Array of argument values that are provided in command line.

### Pre-validation

`PreValidation` modifier can be used to customize the validation of raw string values.
It accepts a function with one of the following signatures:
- `bool validate(string value)`
- `bool validate(string[] value)`
- `bool validate(RawParam param)`

The function should return `true` if validation passed and `false` otherwise.

### Parsing

`Parse` modifier allows providing custom conversion from raw string to typed value.
It accepts a function with one of the following signatures:
- `ParseType parse(string value)`
- `ParseType parse(string[] value)`
- `ParseType parse(RawParam param)`
- `bool parse(ref ParseType receiver, RawParam param)`
- `void parse(ref ParseType receiver, RawParam param)`

Parameters:
- `ParseType` is a type that the string value will be parsed to.
- `value`/`param` values to be parsed.
- `receiver` is an output variable for parsed value.

Parse function is supposed to parse values from `value`/`param` parameter into `ParseType` type and
optionally return boolean type indicating whether parsing was done successfully (`true`) or not (`false`).

### Validation

`Validation` modifier can be used to validate the parsed value.
It accepts a function with one of the following signatures:
- `bool validate(ParseType value)`
- `bool validate(ParseType[] value)`
- `bool validate(Param!ParseType param)`

Parameters:
- `value`/`param` has a value returned from `Parse` step.

The function should return `true` if validation passed and `false` otherwise.

### Action

`Action` modifier allows providing a custom logic of how `receiver` should be changed when argument
has a value in command line.
It accepts a function with one of the following signatures:
- `bool action(ref T receiver, ParseType value)`
- `void action(ref T receiver, ParseType value)`
- `bool action(ref T receiver, Param!ParseType param)`
- `void action(ref T receiver, Param!ParseType param)`

Parameters:
- `receiver` is a receiver (destination field that has `@*Argument` UDA) which is supposed to be changed based on a
 `value`/`param`.
- `value`/`param` has a value returned from `Parse` step.

### Arguments with no values

Sometimes arguments are allowed to have no values in command line. Here are two cases that arise in this situation:

- Argument should get specific default value if there is no value provided in command line.
  `AllowNoValue` modifier should be used in this case.

- Argument must not have any values in command line. In this case `RequireNoValue` modifier should be used. 

Both `AllowNoValue` and `RequireNoValue` modifiers accept a value that should be used when no value
is provided in command line. The difference between them can be seen in this example:  

```d
    struct T
    {
        @(NamedArgument("a").AllowNoValue  !10) int a;
        @(NamedArgument("b").RequireNoValue!20) int b;
    }

    static assert(["-a"].parseCLIArgs!T.get.a == 10);       // use value from UDA
    static assert(["-b"].parseCLIArgs!T.get.b == 20);       // use vlue from UDA
    static assert(["-a", "30"].parseCLIArgs!T.get.a == 30); // providing value is allowed
    assert(["-b", "30"].parseCLIArgs!T.isNull);             // providing value is not allowed
```

### Usage example

All the above modifiers can be combined in any way:

```d
    struct T
    {
        @(NamedArgument("a")
         .PreValidation!((string s) { return s.length > 1 && s[0] == '!'; })
         .Parse        !((string s) { return s[1]; })
         .Validation   !((char v) { return v >= '0' && v <= '9'; })
         .Action       !((ref int a, char v) { a = v - '0'; })
        )
        int a;
    }

    static assert(["-a","!4"].parseCLIArgs!T.get.a == 4);
```

## Config

### Assign character 

`Config.assignChar` - the assignment character used in arguments with value: `-a=5`, `-b=foo`.

Default is equal sign `=`.

### Array separator

`Config.arraySep` - when set to `char.init`, value to array and associative array receivers are
treated as an individual value. That is, only one argument is appended inserted per appearance of
the argument. If `arraySep` is set to something else, then each value is first split by the
separator, and the individual pieces are treated as values to the same argument.

Default is `char.init`.

```d
struct T
{
    @(NamedArgument("a")) string[] a;
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

`Config.caseSensitive` - by default argument names are case-sensitive. You can change that behavior
by setting thia member to `false`.

Default is `true`.

### Bundling of single-letter arguments

`Config.bundling` - when it is set to `true`, single-letter arguments can be bundled together,
i.e. `-abc` is the same as `-a -b -c`.

Default is `false`.

### Error handling

`Config.errorHandler` - this is a handler function for all errors occurred during parsing the
command line. It might be either a function or a delegate that takes `string` parameter which would
be an error message.

The default behavior is to print error message to `stderr`.

