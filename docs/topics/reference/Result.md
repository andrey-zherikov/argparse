# Result struct

`Result` is a struct that is used to communicate between `argparse` and user functions.
Its main responsibility is to hold the result of an operation: success or failure.

## Public members

### Success

`Result.Success` is an compile-time constant (`enum`) that represents a successful result of an operation.

**Signature**
```c++
static enum Success
```

### Error

`Result.Error` is a function that returns a failed result of an operation.

**Signature**

```c++
static auto Error(T...)(int resultCode, string msg, T extraArgs)
```

**Parameters**

- `resultCode`

  Result/exit code of an operation.

- `msg`

  Text of an error message.

- `extraArgs`

  Additional arguments that are added to the text of an error message.

**Notes**

- `msg` and `extraArgs` are converted to a single error message string using `std.conv.text(msg, extraArgs)`.
- Error message supports ANSI styling. See [ANSI coloring and styling](ANSI-coloring-and-styling.md) how to use.
- Error message is passed to [`Config.errorHandler`](Config.md#errorHandler) if it's set or printed to `stderr` otherwise
  by [CLI API](CLI-API.md) at the end of parsing.

**Return value**

`Result` object that represents the failed result of an operation.

### exitCode

`Result.exitCode` is a property that returns the result/exit code. It's supposed to be returned from `main()` function.

**Signature**

```c++
int exitCode() const
```

**Return value**

Result/exit code of an operation.

### opCast

`Result.opCast` can be used to determine whether result of an operation is successful.

**Signature**

```c++
bool opCast(T : bool)() const
```

**Return value**

- `true` if operation is successful.
- `false` otherwise.
