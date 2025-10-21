module argparse.style;

public import argparse.ansi;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Style for printing help screen and error messages
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

public struct Style
{
    // Style for program name.
    TextStyle programName;

    // Style for subcommand name.
    TextStyle subcommandName;

    // Style for title of argument group.
    TextStyle argumentGroupTitle;

    // Style for argument name.
    TextStyle argumentName;

    // Style for value of named argument.
    TextStyle namedArgumentValue;

    // Style for value of positional argument.
    TextStyle positionalArgumentValue;

    // Style for "Error:" prefix in error messages.
    TextStyle errorMessagePrefix;


    // No style
    enum None = Style.init;


    // Default style
    enum Style Default = {
        programName:             bold,
        subcommandName:          bold,
        argumentGroupTitle:      bold.underline,
        argumentName:            lightYellow,
        namedArgumentValue:      italic,
        positionalArgumentValue: lightYellow,
        errorMessagePrefix:      red,
    };
}

unittest
{
    assert(Style.Default.argumentGroupTitle("bbb") == bold.underline("bbb").toString);
    assert(Style.Default.argumentName("bbb") == lightYellow("bbb").toString);
    assert(Style.Default.namedArgumentValue("bbb") == italic("bbb").toString);
}