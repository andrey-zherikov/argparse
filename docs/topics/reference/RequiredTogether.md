# RequiredTogether

`RequiredTogether` UDA is used to mark a set of arguments as mutually required. This means that as soon as one argument from
this group is specified in the command line then all arguments from the same group must also be specified.

See ["Argument dependencies"](Argument-dependencies.md#RequiredTogether) section for more details.

## Required

"Required together" group can be marked as required in order to require all arguments:

```C++
@(RequiredTogether.Required)
{
...
}
```
