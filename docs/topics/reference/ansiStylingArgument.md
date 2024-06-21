# ansiStylingArgument

Almost every command line tool that supports ANSI coloring and styling provides command line argument to control whether
this coloring/styling should be forcefully enabled or disabled.

`argparse` provides `ansiStylingArgument` function that returns an object which allows checking the status of styling/coloring.
This function adds a command line argument that can have one of these values:
- `always` or no value - coloring/styling should be enabled.
- `never` - coloring/styling should be disabled.
- `auto` - in this case, `argparse` will try to detect whether ANSI coloring/styling is supported by a system.

See [ANSI coloring and styling](ANSI-coloring-and-styling.md) for details.

**Signature**

```C++
... ansiStylingArgument()
```

**Usage example**

```C++
static auto color = ansiStylingArgument;
```

> Explicit `static` is not required because returned object has only `static` data members.

**Return value**

Returned object that can be cast to boolean. Its value is `true` when the ANSI coloring/styling should be enabled in the output,
otherwise it's `false`.
