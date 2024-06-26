# Command

`Command` UDA is used to customize **top-level command** as well as **subcommands**.

This UDA can be chained with functions listed below to adjust different settings.

**Signature**

```c++
Command(string[] names...)
```

**Parameters**

- `names`

  For **subcommands**, these are the names of the subcommand that can appear in the command line. If no name is provided then
  the name of the type that represents the command is used.

  For **top-level command**, this is a name of a program/tool that is appeared on help screen. If multiple names are passed, only first is used.
  If no name is provided then `Runtime.args[0]` (a.k.a. `argv[0]` from `main` function) is used.


## Public members

### Usage

`Usage` allows customize the usage text. By default, the parser calculates the usage message from the arguments it contains
but this can be overridden with `Usage` call. If the custom text contains `%(PROG)` then it will be replaced by the
`argv[0]` (from `main` function) in case of top-level command or by a list of commands (all parent commands and current one)
in case of subcommand.


**Signature**

```C++
Usage(auto ref ... command, string text)
Usage(auto ref ... command, string function() text)
```

**Parameters**

- `text`

  Usage text or a function that returns such text.

**Usage example**

```C++
@(Command.Usage("%(PROG) [<parameters>...]"))
struct my_command
{
...
}
```

### Description

`Description` can be used to provide a description of what the command/program does and how it works. In help messages, the
  description is displayed between the usage string and the list of the command arguments.

**Signature**

```C++
Description(auto ref ... command, string text)
Description(auto ref ... command, string function() text)
```

**Parameters**

- `text`

  Text that contains command description or a function that returns such text.

**Usage example**

```C++
@(Command.Description("custom description"))
struct my_command
{
...
}
```

### ShortDescription

`ShortDescription` can be used to provide a brief description of what the subcommand does. It is applicable to subcommands
  only and is displayed in *Available commands* section on help screen of the parent command.

**Signature**

```C++
ShortDescription(auto ref ... command, string text)
ShortDescription(auto ref ... command, string function() text)
```

**Parameters**

- `text`

  Text that contains short description for a subcommand or a function that returns such text.

**Usage example**

```C++
@(Command.ShortDescription("custom description"))
struct my_command
{
...
}
```


### Epilog

`Epilog` can be used to provide some custom text that is printed at the end after the list of command arguments.

**Signature**

```C++
Epilog(auto ref ... command, string text)
Epilog(auto ref ... command, string function() text)
```

**Parameters**

- `text`

  Epilog text or a function that returns such text.

**Usage example**

```C++
@(Command.Epilog("extra info about the command"))
struct my_command
{
...
}
```
