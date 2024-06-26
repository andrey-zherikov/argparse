# Arguments bundling

Some command line tools allow bundling of single-character argument names in a form of `-abc` where `a`, `b` and `c` are
separate arguments. `argparse` supports this through [`Config.bundling`](Config.md#bundling) setting and allows the following usages:

<code-block src="code_snippets/config_bundling.d" lang="c++"/>

To explain what happens under the hood, let's consider that a command line has `-abc` entry and there is no `abc` argument.
In this case, `argparse` tries to parse it as `-a bc` if there is an `a` argument and it accepts a value, or as `-a -bc`
if there is an `a` argument and it does not accept any value. In case if there is no `a` argument, `argparse` will error out.
