import argparse;

struct COMMAND
{
    string a;
    string b;
}

int main(string[] argv)
{
    COMMAND cmd;

    if(!CLI!COMMAND.parseArgs(cmd, argv[1..$]))
        return 1; // parsing failure

    // Do whatever is needed

    return 0;
}
