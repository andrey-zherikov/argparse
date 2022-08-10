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

    private this(ubyte[] st)
    {
        style = st;
    }
    private this(ubyte st)
    {
        if(st != 0)
            style = [st];
    }

    private auto opBinary(string op)(ubyte other) if(op == "~")
    {
        return other != 0 ? TextStyle(style ~ other) : this;
    }

    public auto opCall(string str) const
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
    assert(TextStyle([])("foo") == "foo");
    assert(TextStyle([Font.bold])("foo") == "\033[1mfoo\033[m");
    assert(TextStyle([Font.bold, Font.italic])("foo") == "\033[1;3mfoo\033[m");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct StyledText
{
    TextStyle style;

    string text;

    string toString() const
    {
        return style(text);
    }
}

unittest
{
    auto s = TextStyle([Font.bold]);
    assert(StyledText(s, "foo").toString() == s("foo"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package template StyleImpl(ubyte styleCode)
{
    public auto StyleImpl()
    {
        return TextStyle(styleCode);
    }
    public auto StyleImpl(TextStyle otherStyle)
    {
        return otherStyle ~ styleCode;
    }
    public auto StyleImpl(string text)
    {
        return StyledText(TextStyle(styleCode), text);
    }
    public auto StyleImpl(TextStyle otherStyle, string text)
    {
        return StyledText(otherStyle ~ styleCode, text);
    }
}

alias noStyle      = StyleImpl!(0);

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
    assert(bold("foo").toString() == "\033[1mfoo\033[m");
    assert(bold.italic("foo").toString() == "\033[1;3mfoo\033[m");
    assert(bold.italic.red("foo").toString() == "\033[1;3;31mfoo\033[m");
    assert(bold.italic.red.onWhite("foo").toString() == "\033[1;3;31;107mfoo\033[m");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package size_t getUnstyledTextLength(string text)
{
    import std.regex: ctRegex, matchAll;
    import std.algorithm: map, sum;

    enum re = ctRegex!(`\x1b\[(\d*(;\d*)*)?m`);

    return text.length - text.matchAll(re).map!(_ => _.hit.length).sum;
}

package size_t getUnstyledTextLength(StyledText text)
{
    return getUnstyledTextLength(text.toString());
}

unittest
{
    assert(getUnstyledTextLength("") == 0);
    assert(getUnstyledTextLength(reset) == 0);
    assert(getUnstyledTextLength(bold("foo")) == 3);
    assert(getUnstyledTextLength(bold.italic("foo")) == 3);
    assert(getUnstyledTextLength(bold.italic.red("foo")) == 3);
    assert(getUnstyledTextLength(bold.italic.red.onWhite("foo")) == 3);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package bool detectSupport()
{
    import std.process: environment;

    // https://no-color.org/
    if(environment.get("NO_COLOR") != "")
        return false;

    // https://bixense.com/clicolors/
    if(environment.get("CLICOLOR_FORCE", "0") != "0")
        return true;

    // https://bixense.com/clicolors/
    if(environment.get("CLICOLOR") == "0")
        return false;

    // https://conemu.github.io/en/AnsiEscapeCodes.html#Environment_variable
    auto ConEmuANSI = environment.get("ConEmuANSI");
    if(ConEmuANSI == "OFF")
        return false;
    if(ConEmuANSI == "ON")
        return true;

    // https://github.com/adoxa/ansicon/blob/master/readme.txt
    if(environment.get("ANSICON") !is null)
        return true;

    version(Windows)
    {
        // Is it ran under Cygwin, MSYS, MSYS2? Enable colors if so.
        import std.algorithm: startsWith, find;
        auto term = environment.get("TERM");

        if(term.find("cygwin") || term.startsWith("xterm"))
            return true;

        // ANSI escape sequences are supported since Windows10 v1511 so try to enable it
        import core.sys.windows.winbase: GetStdHandle, STD_OUTPUT_HANDLE, INVALID_HANDLE_VALUE;
        import core.sys.windows.wincon: GetConsoleMode, SetConsoleMode, ENABLE_VIRTUAL_TERMINAL_PROCESSING;

        auto handle = GetStdHandle(STD_OUTPUT_HANDLE);
        if(!handle || handle == INVALID_HANDLE_VALUE)
            return false;

        uint mode;
        if(!GetConsoleMode(handle, &mode))
            return false;

        if(mode & ENABLE_VIRTUAL_TERMINAL_PROCESSING)
            return true; // already enabled

        return SetConsoleMode(handle, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING) != 0;
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

    // Force disable
    assert(!detect("NO_COLOR", "1"));
    assert(!detect("CLICOLOR","0"));
    assert(!detect("ConEmuANSI","OFF"));

    // Force enable
    assert(detect("CLICOLOR_FORCE","1"));
    assert(detect("ANSICON",""));
    assert(detect("ConEmuANSI","ON"));

    // Default behavior
    auto defaultVal = detectSupport();
    assert(detect("CLICOLOR","1") == defaultVal);
    assert(detect("ConEmuANSI","") == defaultVal);
    assert(detect("CLICOLOR_FORCE","0") == defaultVal);

    version(Windows)
    {
        // clean "TERM" env for windows
        auto term = environment.get("TERM");
        scope(exit) environment["TERM"] = term;
        environment.remove("TERM");

        assert(!detectSupport());
    }
}