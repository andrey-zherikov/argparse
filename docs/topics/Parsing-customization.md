# Parsing customization

Sometime the functionality that is provided out of the box is not enough and needs to be tuned.
`argparse` allows customizing of every step of command line parsing:

- **Pre-validation** – argument values are validated as raw strings.
- **Parsing** – raw argument values are converted to a different type (usually the type of the receiving data member).
- **Validation** – converted value is validated.
- **Action** – depending on a type of the receiving data member, for example, it can be an assignment of converted value to a
  data member, or appending value if type is an array.

In case if argument does not have any value to parse, then the only one step is involved in parsing:

- **Action if no value** – similar to **Action** step above but without converted value.

> If any of the steps above fails, then the command line parsing fails as well.
>
{style="note"}

Each of the steps above can be customized with UDA modifiers below.

## Pre-validation {id="PreValidation"}

`PreValidation` modifier can be used to customize the validation of raw string values. It accepts a function with one of
the following signatures:

- `bool   validate(string value)`

  `Result validate(string value)`

  > In this case, function will be called once for every value specified in command line for an argument in case of multiple values.
  >
  {style="note"}

- `bool   validate(string[] value)`

  `Result validate(string[] value)`

- `bool   validate(RawParam param)`

  `Result validate(RawParam param)`

Parameters:

- `value`/`param` values to be parsed.

Return value:

- `true`/`Result.Success` if validation passed or
- `false`/`Result.Error` otherwise.

## Parsing {id="Parse"}

`Parse` modifier allows providing custom conversion from raw string to a typed value. It accepts a function with one of
the following signatures:

- `ParseType parse(string value)`

  `ParseType parse(string[] value)`

  `ParseType parse(RawParam param)`

  > `ParseType` is a type that a string value is supposed to be parsed to and it is not required be the same as
  a type of destination - `argparse` tries to detect this type from provided function.
  >
  > `ParseType` must not be immutable or const.
  >
  {title="ParseType"}

- `void   parse(ref ParseType receiver, RawParam param)`

  `bool   parse(ref ParseType receiver, RawParam param)`

  `Result parse(ref ParseType receiver, RawParam param)`


Parameters:

- `value`/`param` raw (string) values to be parsed.
- `receiver` is an output variable for parsed value.

Return value for functions that return `bool` or `Result` (in other cases parsing is always considered successful):
- `true`/`Result.Success` if parsing was successful or
- `false`/`Result.Error` otherwise.

## Validation {id="Validation"}

`Validation` modifier can be used to validate parsed value. It accepts a function with one of the following
signatures:

- `bool   validate(ParseType value)`

  `Result validate(ParseType value)`

- `bool   validate(Param!ParseType param)`

  `Result validate(Param!ParseType param)`

> `ParseType` is a type that is used in `Parse` modifier or `string` if the latter is omitted.
>
{title="ParseType"}

Parameters:

- `value`/`param` contains a value returned from `Parse` step.

Return value:

- `true`/`Result.Success` if validation passed or
- `false`/`Result.Error` otherwise.

## Action {id="Action"}

`Action` modifier allows customizing a logic of how "destination" should be changed when argument has a value in
command line. It accepts a function with one of the following signatures:

- `void   action(ref T receiver, ParseType value)`

  `bool   action(ref T receiver, ParseType value)`

  `Result action(ref T receiver, ParseType value)`

- `void   action(ref T receiver, Param!ParseType param)`

  `bool   action(ref T receiver, Param!ParseType param)`

  `Result action(ref T receiver, Param!ParseType param)`

> `ParseType` is a type that is used in `Parse` modifier or `string` if the latter is omitted.
>
{title="ParseType"}

Parameters:

- `receiver` is a receiver (destination) which is supposed to be changed based on a `value`/`param`.
- `value`/`param` has a value returned from `Parse` step.

Return value:

- `true`/`Result.Success` if operation was successful or
- `false`/`Result.Error` otherwise.

## Example

All the above modifiers can be combined in any way:

<code-block src="code_snippets/parsing_customization.d" lang="c++"/>
