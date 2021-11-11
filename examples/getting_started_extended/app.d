import argparse;

static struct Extended
{
	// Positional arguments are required by default
	@PositionalArgument(0)
	string name;

	// Named arguments can be attributed in bulk (parentheses can be omitted)
	@NamedArgument
	{
		string unused = "some default value";
		int number;
		bool boolean;
	}

	// Named argument can have custom or multiple names
	@NamedArgument("apple","appl")
	int apple;

	@NamedArgument(["b","banana","ban"])
	int banana;
}

mixin Main.parseCLIArgs!(Extended, (args)
{
	// do whatever you need
	return 0;
});