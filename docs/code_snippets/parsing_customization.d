import argparse;

struct T
{
    @(NamedArgument
    .PreValidation((string s) { return s.length > 1 && s[0] == '!'; })
    .Parse        ((string s) { return cast(char) s[1]; })
    .Validation   ((char v) { return v >= '0' && v <= '9'; })
    .Action       ((ref int a, char v) { a = v - '0'; })
    )
    int a;
}

T t;
assert(CLI!T.parseArgs(t, ["-a","!4"]));
assert(t == T(4));
