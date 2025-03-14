# Param / RawParam

[Parsing customization API](Parsing-customization.md) works with Param/RawParam struct under the hood which is publicly available for usage.

`Param` is a template struct parametrized by `VALUE_TYPE` (see below) which is usually a `string[]` or a type of destination data member.

> `RawParam` is an alias where `VALUE_TYPE` is `string[]`. This alias represents "raw" values from command line.
>
{style="note"}

`Param` struct has the following fields:

- `const(Config)*` `config`- The content is almost the same as the [`Config`](Config.md) object that was passed into [CLI API](CLI-API.md).
  The only difference is in [`Config.stylingMode`](Config.md#stylingMode) - it is either `Config.StylingMode.on` or `Config.StylingMode.off`
  based on [auto-detection](ANSI-coloring-and-styling.md#heuristic) results.
- `string` `name` – For named argument, it contains a name that is specified in command line exactly including prefix(es)
  ([`Config.shortNamePrefix`](Config.md#shortNamePrefix)/[`Config.longNamePrefix`](Config.md#longNamePrefix)).
  For positional arguments, it contains placeholder value.
- `VALUE_TYPE` `value` – Argument values that are provided in command line.
