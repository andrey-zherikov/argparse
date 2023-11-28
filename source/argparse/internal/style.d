module argparse.internal.style;

import argparse.ansi;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Styling options
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct Style
{
    TextStyle programName;
    TextStyle subcommandName;
    TextStyle argumentGroupTitle;
    TextStyle argumentName;
    TextStyle namedArgumentValue;
    TextStyle positionalArgumentValue;

    TextStyle errorMessagePrefix;

    enum None = Style.init;

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