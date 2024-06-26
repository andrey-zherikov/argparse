import argparse;

struct T
{
    string a;
}

enum Config cfg = {
    errorHandler:
        (text)
        {
            try {
                import std.stdio : stderr;
                stderr.writeln("Detected an error: ", text);
            }
            catch(Exception e)
            {
                throw new Error(e.msg);
            }
        }
};

T t;
assert(!CLI!(cfg, T).parseArgs(t, ["-b"]));
