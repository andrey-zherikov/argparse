import argparse;

struct T
{
    @(NamedArgument.Required)
    string a;
}

// Only the error message is printed (default)
T t1;
assert(CLI!T.parseArgs(t1, []).isError);

// Usage line is printed to stderr in front of the error message
enum Config cfgUsage = { helpOnError: Config.HelpOnError.usage };

T t2;
assert(CLI!(cfgUsage, T).parseArgs(t2, []).isError);

// The whole help screen is printed instead
enum Config cfgFull = { helpOnError: Config.HelpOnError.full };

T t3;
assert(CLI!(cfgFull, T).parseArgs(t3, []).isError);
