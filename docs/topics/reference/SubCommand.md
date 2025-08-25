# SubCommand

`SubCommand` type can be used to enumerate type for subcommands. This is a wrapper of `SumType`:

```c++
struct SubCommand(Commands...)
```

## Public members

### Copy constructor

**Signature**

```c++
this(T)(T value)
```

**Parameters**

- `T value`

  Value that is copied to a new object. Its type `T` must be one of the `Commands`.

### Assignment operator

**Signature**

```c++
ref SubCommand opAssign(T)(T value)
```

**Parameters**

- `T value`

  Value to be assigned. Its type `T` must be one of the `Commands`.

### isSetTo

Checks whether the object is set to a specific command type;

**Signature**

```c++
bool isSetTo(T)() const
```

**Parameters**

- `T`

  Type `T` must be one of the `Commands`.

**Return value**

`true` if object contains `T` type, `false` otherwise.

### isSet

Checks whether the object is set to any command type;

**Signature**

```c++
bool isSet() const
```

**Return value**

If one of the `Commands` is a default command then this function always returns `true`.

In case if there is no default command, then:
- `true` if object contains any type from `Commands`, `false` otherwise.

## Default

`Default` type is a struct that can be used to mark a subcommand as default, i.e. it's chosen if no other subcommand is specified
in command line explicitly.

This struct has no members and is erased by `SubCommand` before passing to internal `SumType` member.

**Signature**

```c++
struct Default(COMMAND)
```

## matchCmd

`matchCmd` is a function template that is similar to `std.sumtype.match` but adapted to work with `SubCommand`.

**Signature**

```c++
template matchCmd(handlers...)
{
  auto ref matchCmd(Sub : const SubCommand!Args, Args...)(auto ref Sub sc)
  ...
}
```

**Parameters**

- `handlers`

  Functions that have the same meaning as for `matchCmd` function in standard library with an exception that they must not use `Default`
  type because the latter is erased by `SubCommand` (i.e. just use `T` instead of `Default!T` here).

- `sc`

  `SubCommand` parameter that the matching is applied to.

**Return value**

- If `sc` is set to any subcommand (or has default one) then function returns the result from `std.sumtype.match` function.
- Otherwise, `init` value of the type that would be returned from `std.sumtype.match` function if that type is not `void`.
- Otherwise, this function has no return value (i.e. it's `void`).
