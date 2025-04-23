# PositionalArgument/NamedArgument

`NamedArgument` UDA is used to declare an argument that has a name (usually starting with `-` or `--`).

`PositionalArgument` UDA is used to declare an argument that has specific position in the command line.


**Signature**

```c++
PositionalArgument()
PositionalArgument(uint position)
PositionalArgument(uint position, string placeholder)
NamedArgument(string[] names...)
NamedArgument(string[] shortNames, string[] longNames)
```

**Parameters**

- `position`

  Zero-based position of the argument. If it's omitted then positional arguments have an order of their declaration.

- `placeholder`

  Name of this argument that is shown in help text.
  By default, the name of data member is used.

- `names`

  Name(s) of this argument that can be used in command line.
  By default, the name of data member is used.

- `shortNames`

  Short name(s) of this argument that can be used in command line.

- `longNames`

  Long name(s) of this argument that can be used in command line.

## Public members

### Description

`Description` can be used to provide a description of the argument. This text is printed next to the argument
in the argument list section of a help message.

**Signature**

```C++
Description(auto ref ... argument, string text)
Description(auto ref ... argument, string function() text)
```

**Parameters**

- `text`

  Text that contains argument description or a function that returns such text.

**Usage example**

```C++
struct my_command
{
  @(NamedArgument.Description("custom description"))
  int a;
}
```

### Hidden

`Hidden` can be used to indicate that the argument should not be printed in help message or returned in shell completion.

**Signature**

```C++
Hidden(auto ref ... argument, bool hide = true)
```

**Parameters**

- `hide`

  If `true` then argument is not printed in help message.

**Usage example**

```C++
struct my_command
{
  @(NamedArgument.Hidden)
  int a;
}
```

### Placeholder

`Placeholder` provides custom text that is used to indicate the value of the argument in help message.

**Signature**

```C++
Placeholder(auto ref ... argument, string value)
```

**Parameters**

- `value`

  Text that is used as a placeholder for a value of an argument in help message.

**Usage example**

```C++
struct my_command
{
  @(NamedArgument.Placeholder("VALUE"))
  int a;
}
```

### Required

Mark an argument as required so if it is not provided in command line, `argparse` will error out.

By default all positional arguments are required.

**Signature**

```C++
Required(auto ref ... argument)
```

**Usage example**

```C++
struct my_command
{
  @(NamedArgument.Required)
  int a;
}
```

### Optional

Mark an argument as optional so it can be omitted in command line without causing errors.

By default all named arguments are optional.

**Signature**

```C++
Optional(auto ref ... argument)
```

**Usage example**

```C++
struct my_command
{
  @(NamedArgument.Optional)
  int a;
}
```

### NumberOfValues

`NumberOfValues` is used to limit number of values that an argument can accept.

**Signature**

```C++
NumberOfValues(auto ref ... argument, size_t min, size_t max)
NumberOfValues(auto ref ... argument, size_t num)
```

**Parameters**

- `min`

  Minimum number of values.

- `max`

  Maximum number of values.

- `num`

  Exact number of values.

**Usage example**

```C++
struct my_command
{
  @(NamedArgument.NumberOfValues(1,3))
  int[] a;

  @(NamedArgument.NumberOfValues(2))
  int[] b;
}
```

### MinNumberOfValues

`MinNumberOfValues` is used to set minimum number of values that an argument can accept.

**Signature**

```C++
MinNumberOfValues(auto ref ... argument, size_t min)
```

**Parameters**

- `min`

  Minimum number of values.

**Usage example**

```C++
struct my_command
{
  @(NamedArgument.MinNumberOfValues(2))
  int[] a;
}
```

### MaxNumberOfValues

`MaxNumberOfValues` is used to set maximum number of values that an argument can accept.

**Signature**

```C++
MaxNumberOfValues(auto ref ... argument, size_t max)
```

**Parameters**

- `max`

  Maximum number of values.

**Usage example**

```C++
struct my_command
{
  @(NamedArgument.MinNumberOfValues(3))
  int[] a;
}
```

### AllowNoValue

`AllowNoValue` allows an argument to not have a value in the command line - in this case, the value provided to this function will be used.

**Signature**

```C++
AllowNoValue(VALUE)(auto ref ... argument, VALUE valueToUse)
```

**Parameters**

- `valueToUse`

  Value that is used when argument has no value specified in command line.

**Usage example**

```C++
struct my_command
{
  @(NamedArgument.AllowNoValue(10))
  int a;
}
```

### ForceNoValue

`ForceNoValue` forces an argument to have no value in the command line. The argument is behaving like a boolean flag
but instead of `true`/`false` values, there can be either a value provided to `ForceNoValue` or a default one (`.init`).

**Signature**

```C++
ForceNoValue(VALUE)(auto ref ... argument, VALUE valueToUse)
```

**Parameters**

- `valueToUse`

  Value that is used when argument is specified in command line.

**Usage example**

```C++
struct my_command
{
  @(NamedArgument.ForceNoValue(10))
  int a;
}
```

### AllowedValues

`AllowedValues` can be used to restrict what value can be provided in the command line for an argument.

**Signature**

```C++
AllowedValues(TYPE)(auto ref ... argument, TYPE[] values...)
```

**Parameters**

- `values`

  List of values that an argument can have.

**Usage example**

```C++
struct my_command
{
  @(NamedArgument.AllowedValues(1,4,16,8))
  int a;
}
```

### Counter

`Counter` can be used to mark an argument that tracks the number of times it's specified in the command line.

**Signature**

```C++
Counter(auto ref ... argument)
```

**Usage example**

```C++
struct my_command
{
  @(NamedArgument.Counter)
  int a;
}
```

### PreValidation

`PreValidation` can be used to customize the validation of raw string values.

**Signature**

```C++
PreValidation(auto ref ... argument, RETURN function(VALUE value) func)
```

**Parameters**

- `func`

  Function that is called to validate raw value. See [parsing customization](Parsing-customization.md#PreValidation) for details.

**Usage example**

```C++
struct my_command
{
  @(NamedArgument.PreValidation((string s) { return s.length > 0;}))
  int a;
}
```

### Parse

`Parse` can be used to provide custom conversion from raw string to a value.

**Signature**

```C++
Parse(auto ref ... argument, RECEIVER function(VALUE value) func)
Parse(auto ref ... argument, RETURN function(ref RECEIVER receiver, RawParam param) func)
```

**Parameters**

- `func`

  Function that is called to convert raw value. See [parsing customization](Parsing-customization.md#Parse) for details.

**Usage example**

```C++
struct my_command
{
  @(NamedArgument.Parse((string s) { return s[1]; }))
  char a;
}
```

### Validation

`Validation` can be used to validate parsed value.

**Signature**

```C++
Validation(auto ref ... argument, RETURN function(VALUE value) func)
```

**Parameters**

- `func`

  Function that is called to validate the value. See [parsing customization](Parsing-customization.md#Validation) for details.

**Usage example**

```C++
struct my_command
{
  @(NamedArgument.Validation((int a) { return a >= 0 && a <= 9; }))
  int a;
}
```

### Action

`Action` can be used to customize a logic of how "destination" should be changed based on parsed argument value.

**Signature**

```C++
Action(auto ref ... argument, RETURN function(ref RECEIVER receiver, VALUE value) func)
```

**Parameters**

- `func`

  Function that is called to update the destination. See [parsing customization](Parsing-customization.md#Action) for details.

**Usage example**

```C++
struct my_command
{
  @(NamedArgument.Action((ref int a, int v) { a += v; })
  int a;
}
```
