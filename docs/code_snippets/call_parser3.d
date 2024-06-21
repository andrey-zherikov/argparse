import argparse;

struct COMMAND
{
    string a;
    string b;
}

static int my_main(COMMAND command)
{
    // Do whatever is needed
    return 0;
}

int main(string[] args)
{
    // Do initialization here
    // If needed, termination code can be done as 'scope(exit) { ...code... }' here as well

    return CLI!COMMAND.parseArgs!my_main(args[1..$]);
}
