# printHelp

`argparse` provides set of `printHelp` functions to print help messages.

**Signature**
```c++
void printHelp(Config config, COMMAND...)()
void printHelp(Config config, COMMAND...)(void delegate(string) sink)
```

**Parameters**

- `config`

  [`Config`](Config.md) object that is expected to be the same as the one passed to [`CLI API`](CLI-API.md). Note that
  only the first function checks for [`config.helpPrinter`](Config.md#helpPrinter) and calls it if it's set.

- `COMMAND...`

  List of types representing subcommand hierarchy starting with top-level, for example: `TOP_LEVEL_CMD, SUBCMD1, SUBCMD1_2`
  (where `SUBCMD1_2` is a subcommand of `SUBCMD1`).

- `sink`

  Delegate that is called with help text. `argparse` calls this delegate multiple times passing help text by pieces -
  as soon as they are formatted and ready to be printed.
