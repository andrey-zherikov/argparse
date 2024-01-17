// This example shows the usage of a single entry for both a program and a completer

import argparse;

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

// This mixin defines standard main function that parses command line and prints completion result to stdout
mixin CLI!Program.main!((prog)
{
    version(argparse_completion)
    {
        // This function is never used when 'argparse_completion' version is defined
        static assert(false);
    }
});