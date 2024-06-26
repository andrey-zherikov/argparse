import argparse;

struct Params
{
    // If name is not provided then member name is used: "--greeting"
    @NamedArgument
    string greeting;

    // If member name is single character then it becomes a short name: "-a"
    @NamedArgument
    string a;

    // Argument with multiple names: "--name", "--first-name", "-n"
    // Note that single character becomes a short name
    @NamedArgument(["name", "first-name", "n"])
    string name;

    // Another way to specify multiple names: "--family", "--last-name"
    @NamedArgument("family", "last-name")
    string family;
}
