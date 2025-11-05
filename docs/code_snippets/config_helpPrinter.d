import argparse;

struct T
{
    string a;
}

enum Config cfg = {
    helpPrinter:
        function (Style style, CommandHelpInfo[] cmds)
        {
            import std.stdio : stderr;
            scope auto output = stderr.lockingTextWriter();

            new HelpPrinter(style).printHelp(_ => output.put(_), cmds);
        }
};

T t;
assert(!CLI!(cfg, T).parseArgs(t, ["-h"]));
