import argparse;

struct cmd1
{
    string a;
}

struct cmd2
{
    string b;
}

mixin CLI!(cmd1, cmd2).main!((args, unparsed)
{
    // 'args' has either 'cmd1' or 'cmd2' type
    static if(is(typeof(args) == cmd1))
        writeln("cmd1: ", args);
    else static if(is(typeof(args) == cmd2))
        writeln("cmd2: ", args);
    else
        static assert(false); // this would never happen

    // unparsed arguments has 'string[]' type
    static assert(is(typeof(unparsed) == string[]));

    return 0;
});
