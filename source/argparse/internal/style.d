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
    TextStyle namedArgumentName;
    TextStyle namedArgumentValue;
    TextStyle positionalArgumentValue;

    enum None = Style.init;

    enum Default = Style(
        bold,           // programName
        bold,           // subcommandName
        bold.underline, // argumentGroupTitle
        lightYellow,    // namedArgumentName
        italic,         // namedArgumentValue
        lightYellow,    // positionalArgumentValue
    );
}

unittest
{
    assert(Style.Default.argumentGroupTitle("bbb") == bold.underline("bbb").toString);
    assert(Style.Default.namedArgumentName("bbb") == lightYellow("bbb").toString);
    assert(Style.Default.namedArgumentValue("bbb") == italic("bbb").toString);
}