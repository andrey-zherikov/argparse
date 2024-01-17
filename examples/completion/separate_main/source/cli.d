module cli;

import argparse: SubCommand;

struct cmd1
{
    string car;
    string can;
    string ban;
}
struct cmd2 {}

struct Program
{
    string foo, bar, baz;

    SubCommand!(cmd1, cmd2) cmd;
}