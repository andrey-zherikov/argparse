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

    enum Default = Style(
        bold,           // programName
        bold,           // subcommandName
        bold.underline, // argumentGroupTitle
        lightYellow,    // argumentName
        italic,         // namedArgumentValue
        lightYellow,    // positionalArgumentValue
        red,            // errorMessagePrefix
    );
}

unittest
{
    assert(Style.Default.argumentGroupTitle("bbb") == bold.underline("bbb").toString);
    assert(Style.Default.argumentName("bbb") == lightYellow("bbb").toString);
    assert(Style.Default.namedArgumentValue("bbb") == italic("bbb").toString);
}