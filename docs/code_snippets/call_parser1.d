import argparse;

struct T
{
    string a;
    string b;
}

mixin CLI!T.main!((args)
{
    // 'args' has 'T' type
    static assert(is(typeof(args) == T));

    // do whatever you need
    import std.stdio: writeln;
    args.writeln;
    return 0;
});
