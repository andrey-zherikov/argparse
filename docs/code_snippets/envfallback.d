import argparse;

version (Windows)
    immutable UserVariable = "USERNAME";
else
    immutable UserVariable = "USER";

struct T
{
    @(PositionalArgument.EnvFallback("XDG_RUNTIME_DIR"))
    string dir;

    @(NamedArgument.EnvFallback(UserVariable))
    string user;
}

// This can be called argument-less on most Linux machines as both variables
// will be set. Calling with `./myprog some/path` will use `some/path` for `dir`,
// and `--user username` will take precedence over the `$USER` or `%USERNAME%
// environment variable.
