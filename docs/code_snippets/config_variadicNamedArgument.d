import argparse;

struct T
{
    @NamedArgument
    int[] a;
}

{
    T t;
    assert(CLI!T.parseArgs(t, ["-a", "1", "-a", "2", "-a", "3"]));
    assert(t == T([1, 2, 3]));
}
{
    enum Config config = { variadicNamedArgument: true };
    T t;
    assert(CLI!(config, T).parseArgs(t, ["-a", "1", "2", "3"]));
    assert(t == T([1, 2, 3]));
}
