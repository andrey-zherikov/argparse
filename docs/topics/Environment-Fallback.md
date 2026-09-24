# Fallback to environment variable

Arguments can be marked to fall back to environment variable if no value is provided on the command line. This allows to implement convenient fallback mechanisms (such as automatically picking up the username) or [12 Factor Apps](https://12factor.net/).

To enable the fallback, use `EnvFallback` modifier with the name of the environment variable. It works for both
positional and named arguments. The value is taken in this order:
- If the argument is provided in command line, then that value is used and the environment variable is ignored.
- Otherwise, if the environment variable is set, then its value is parsed the same way as a single value from command
  line would be. Note that a variable that is set to an empty string is still taken into account.
- Otherwise, the data member keeps its initial value.

A value that comes from the environment variable satisfies [`Required`](Optional-and-required-arguments.md) argument,
so such argument can be omitted from command line as long as the variable is set.

Example:

<code-block src="code_snippets/envfallback.d" lang="c++"/>
