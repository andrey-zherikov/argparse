# HelpScreen

`HelpScreen` provides all information that is needed to print help screen.

## Public nested data types

### Parameter

`Parameter` is a struct that contains the following data members:

- `string name` - name of a parameter.
- `string description` - description of a parameter.

These data members are usually printed as:
```
name    line 1 of description
        line 2 of description
        ...
```

### Group

`Group` is a struct that contains the following data members:

- `string title` - title of a group.
- `string description` - description of a group.
- `Parameter[] parameters` - parameters that belong to a group.

These data members are usually printed as:
```
title:
  description

  parameter
  parameter
  ...
```

## Public data members

`HelpScreen` itself is a struct that contains the following data members:

- `string usage` - usage string.
- `string description` - description that is printed on at top of the help screen.
- `string epilog` - epilog that is printed on in the end of the help screen.
- `Group[] groups` - groups of parameters.

These data members are usually printed as:
```
usage
  description

  group
    ...

  group
    ...
  ...

  epilog
```