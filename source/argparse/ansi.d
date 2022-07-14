module argparse.ansi;

// The string that starts an ANSI command sequence.
private enum prefix = "\033[";

// The character that delimits ANSI parameters.
private enum separator = ";";

// The character used to denote that the sequence is an SGR sequence.
private enum suffix = "m";

// The sequence used to reset all styling.
private enum reset = prefix ~ suffix;

// Code offset between foreground and background
private enum colorBgOffset = 10;

// Styling options
private enum Font
{
    bold      = 1,
    italic    = 3,
    underline = 4,
}

// Standard 4-bit colors
private enum Color
{
    black        = 30,
    red          = 31,
    green        = 32,
    yellow       = 33,
    blue         = 34,
    magenta      = 35,
    cyan         = 36,
    lightGray    = 37,

    darkGray     = 90,
    lightRed     = 91,
    lightGreen   = 92,
    lightYellow  = 93,
    lightBlue    = 94,
    lightMagenta = 95,
    lightCyan    = 96,
    white        = 97
}

package struct TextStyle
{
    private ubyte[] style;

    private auto opBinary(string op)(ubyte other) if(op == "~")
    {
        return TextStyle(style ~ other);
    }

    auto apply(string str) const
    {
        import std.conv: text, to;
        import std.algorithm: joiner, map;
        import std.range: chain;

        if(style.length == 0 || str.length == 0)
            return str;

        return text(prefix, style.map!(to!string).joiner(separator), suffix, str, reset);
    }
}

unittest
{
    assert(TextStyle([]).apply("foo") == "foo");
    assert(TextStyle([Font.bold]).apply("foo") == "\033[1mfoo\033[m");
    assert(TextStyle([Font.bold, Font.italic]).apply("foo") == "\033[1;3mfoo\033[m");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct StyledText
{
    TextStyle style;

    string text;

    @property auto get()
    {
        return style.apply(text);
    }
}

unittest
{
    auto s = TextStyle([Font.bold]);
    assert(StyledText(s, "foo").get == s.apply("foo"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package template StyleImpl(ubyte styleCode)
{
    auto StyleImpl()
    {
        return TextStyle([styleCode]);
    }
    auto StyleImpl(TextStyle otherStyle)
    {
        return otherStyle ~ styleCode;
    }
    auto StyleImpl(string text)
    {
        return StyledText(TextStyle([styleCode]), text);
    }
    auto StyleImpl(TextStyle otherStyle, string text)
    {
        return StyledText(otherStyle ~ styleCode, text);
    }
}

alias bold         = StyleImpl!(Font.bold);
alias italic       = StyleImpl!(Font.italic);
alias underline    = StyleImpl!(Font.underline);

alias black        = StyleImpl!(Color.black);
alias red          = StyleImpl!(Color.red);
alias green        = StyleImpl!(Color.green);
alias yellow       = StyleImpl!(Color.yellow);
alias blue         = StyleImpl!(Color.blue);
alias magenta      = StyleImpl!(Color.magenta);
alias cyan         = StyleImpl!(Color.cyan);
alias lightGray    = StyleImpl!(Color.lightGray);
alias darkGray     = StyleImpl!(Color.darkGray);
alias lightRed     = StyleImpl!(Color.lightRed);
alias lightGreen   = StyleImpl!(Color.lightGreen);
alias lightYellow  = StyleImpl!(Color.lightYellow);
alias lightBlue    = StyleImpl!(Color.lightBlue);
alias lightMagenta = StyleImpl!(Color.lightMagenta);
alias lightCyan    = StyleImpl!(Color.lightCyan);
alias white        = StyleImpl!(Color.white);

alias onBlack        = StyleImpl!(colorBgOffset + Color.black);
alias onRed          = StyleImpl!(colorBgOffset + Color.red);
alias onGreen        = StyleImpl!(colorBgOffset + Color.green);
alias onYellow       = StyleImpl!(colorBgOffset + Color.yellow);
alias onBlue         = StyleImpl!(colorBgOffset + Color.blue);
alias onMagenta      = StyleImpl!(colorBgOffset + Color.magenta);
alias onCyan         = StyleImpl!(colorBgOffset + Color.cyan);
alias onLightGray    = StyleImpl!(colorBgOffset + Color.lightGray);
alias onDarkGray     = StyleImpl!(colorBgOffset + Color.darkGray);
alias onLightRed     = StyleImpl!(colorBgOffset + Color.lightRed);
alias onLightGreen   = StyleImpl!(colorBgOffset + Color.lightGreen);
alias onLightYellow  = StyleImpl!(colorBgOffset + Color.lightYellow);
alias onLightBlue    = StyleImpl!(colorBgOffset + Color.lightBlue);
alias onLightMagenta = StyleImpl!(colorBgOffset + Color.lightMagenta);
alias onLightCyan    = StyleImpl!(colorBgOffset + Color.lightCyan);
alias onWhite        = StyleImpl!(colorBgOffset + Color.white);


unittest
{
    assert(bold == TextStyle([Font.bold]));
    assert(bold.italic == TextStyle([Font.bold, Font.italic]));
    assert(bold.italic.red == TextStyle([Font.bold, Font.italic, Color.red]));
    assert(bold.italic.red.onWhite == TextStyle([Font.bold, Font.italic, Color.red, colorBgOffset + Color.white]));
    assert(bold("foo").get == "\033[1mfoo\033[m");
    assert(bold.italic("foo").get == "\033[1;3mfoo\033[m");
    assert(bold.italic.red("foo").get == "\033[1;3;31mfoo\033[m");
    assert(bold.italic.red.onWhite("foo").get == "\033[1;3;31;107mfoo\033[m");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package bool detectSupport()
{
    import std.process: environment;

    string value;

    // https://no-color.org/
    if(environment.get("NO_COLOR") !is null)
        return false;

    // https://bixense.com/clicolors/
    value = environment.get("CLICOLOR_FORCE");
    if(value !is null && value != "0")
        return true;

    // https://bixense.com/clicolors/
    if(environment.get("CLICOLOR") == "0")
        return false;

    // https://conemu.github.io/en/AnsiEscapeCodes.html#Environment_variable
    if(environment.get("ConEmuANSI") == "OFF")
        return false;

    // https://github.com/adoxa/ansicon/blob/master/readme.txt
    if(environment.get("ANSICON") !is null)
        return true;

    // https://bixense.com/clicolors/
    if(environment.get("CLICOLOR") == "1")
        return true;

    // https://conemu.github.io/en/AnsiEscapeCodes.html#Environment_variable
    if(environment.get("ConEmuANSI") == "ON")
        return true;

    version(Windows)
    {
        // Is it ran under Cygwin, MSYS, MSYS2? Enable colors if so.
        import std.algorithm: startsWith, find;
        auto term = environment.get("TERM");

        return term.find("cygwin") || term.startsWith("xterm");
    }
    else version(Posix)
    {
        // Is stdout redirected? No colors if so.
        import core.sys.posix.unistd: isatty, STDOUT_FILENO;
        return isatty(STDOUT_FILENO) == 1;
    }
    else
    {
        return false;
    }
}

version(unittest)
{
package auto cleanStyleEnv(bool forceNoColor = false)
{
    import std.process: environment;

    string[string] vals;
    foreach(var; ["NO_COLOR","CLICOLOR","CLICOLOR_FORCE","ConEmuANSI","ANSICON"])
    {
        vals[var] = environment.get(var);
        environment.remove(var);
    }

    if(forceNoColor)
        environment["NO_COLOR"] = "";

    return vals;
}

package void restoreStyleEnv(string[string] vals)
{
    import std.process: environment;

    foreach(var, val; vals)
        if(val !is null)
            environment[var] = val;
}
}

unittest
{
    import std.process: environment;

    auto env = cleanStyleEnv();
    scope(exit) restoreStyleEnv(env);

    bool detect(string var, string val)
    {
        environment[var] = val;
        scope(exit)
            environment.remove(var);

        return detectSupport();
    }

    assert(!detect("NO_COLOR", ""));
    assert(!detect("CLICOLOR","0"));
    assert(!detect("ConEmuANSI","OFF"));

    assert(detect("CLICOLOR_FORCE","1"));
    assert(detect("ANSICON",""));
    assert(detect("CLICOLOR","1"));
    assert(detect("ConEmuANSI","ON"));

    assert(detect("CLICOLOR_FORCE","0") == detectSupport());

    version(Windows)
    {
        // clean "TERM" env for windows
        auto term = environment.get("TERM");
        scope(exit) environment["TERM"] = term;
        environment.remove("TERM");

        assert(!detectSupport());
    }
}