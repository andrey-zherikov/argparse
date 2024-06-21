# MutuallyExclusive

`MutuallyExclusive` UDA is used to mark a set of arguments as mutually exclusive. This means that as soon as one argument from
this group is specified in the command line then no other arguments from the same group can be specified.

See ["Argument dependencies"](Argument-dependencies.md#MutuallyExclusive) section for more details.

## Required

"Mutually exclusive" group can be marked as required in order to require exactly one argument from the group:

```C++
@(MutuallyExclusive.Required)
{
    int a;
    int b;
}
```
