module cli;

struct cmd1
{
    string car;
    string can;
    string ban;
}
struct cmd2 {}

struct Program
{
    import std.sumtype: SumType;

    string foo, bar, baz;

    SumType!(cmd1, cmd2) cmd;
}