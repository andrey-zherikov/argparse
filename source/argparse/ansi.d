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
    private string style = prefix;

    private this(scope const(ubyte)[] st...) scope inout nothrow pure @safe
    {
        import std.algorithm.iteration: joiner, map;
        import std.array: appender;
        import std.conv: toChars;
        import std.utf: byCodeUnit;

        auto a = appender(prefix);
        a ~= st.map!(_ => uint(_).toChars).joiner(separator.byCodeUnit);
        style = a[];
    }

    private ref opOpAssign(string op : "~")(ubyte other)
    {
        import std.array: appender;
        import std.conv: toChars;

        if(other != 0)
        {
            auto a = appender(style);
            if(style.length != prefix.length)
                a ~= separator;
            a ~= uint(other).toChars;
            style = a[];
        }
        return this;
    }

    public auto opCall(string str) const
    {
        if(str.length == 0 || style.length == prefix.length)
            return str;
        return style ~ suffix ~ str ~ reset;
    }
}

nothrow pure @safe unittest
{
    assert(TextStyle.init("foo") == "foo");
    assert(TextStyle([])("foo") == "foo");
    assert(TextStyle([Font.bold])("foo") == "\033[1mfoo\033[m");
    assert(TextStyle([Font.bold, Font.italic])("foo") == "\033[1;3mfoo\033[m");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private struct StyledText
{
    TextStyle style;

    string text;

    string toString() return scope const nothrow pure @safe
    {
        return style(text);
    }

    // this ~ rhs
    string opBinary(string op : "~")(string rhs) const
    {
        return toString() ~ rhs;
    }

    // lhs ~ this
    string opBinaryRight(string op : "~")(string lhs) const
    {
        return lhs ~ toString();
    }
}

nothrow pure @safe unittest
{
    auto s = TextStyle([Font.bold]);
    assert(StyledText(s, "foo").toString() == s("foo"));

    const ubyte[1] data = [Font.bold];
    scope c = const TextStyle(data);
    assert((const StyledText(c, "foo")).toString() == c("foo"));

    immutable foo = StyledText(s, "foo");
    assert(foo ~ "bar" == s("foo") ~ "bar");
    assert("bar" ~ foo == "bar" ~ s("foo"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package template StyleImpl(ubyte styleCode)
{
    immutable style = TextStyle(styleCode);

    public TextStyle StyleImpl()
    {
        return style;
    }
    public auto StyleImpl(TextStyle otherStyle)
    {
        return otherStyle ~= styleCode;
    }
    public auto StyleImpl(string text)
    {
        return StyledText(style, text);
    }
    public auto StyleImpl(TextStyle otherStyle, string text)
    {
        return StyledText(otherStyle ~= styleCode, text);
    }
}

public alias noStyle      = StyleImpl!(0);

public alias bold         = StyleImpl!(Font.bold);
public alias italic       = StyleImpl!(Font.italic);
public alias underline    = StyleImpl!(Font.underline);

public alias black        = StyleImpl!(Color.black);
public alias red          = StyleImpl!(Color.red);
public alias green        = StyleImpl!(Color.green);
public alias yellow       = StyleImpl!(Color.yellow);
public alias blue         = StyleImpl!(Color.blue);
public alias magenta      = StyleImpl!(Color.magenta);
public alias cyan         = StyleImpl!(Color.cyan);
public alias lightGray    = StyleImpl!(Color.lightGray);
public alias darkGray     = StyleImpl!(Color.darkGray);
public alias lightRed     = StyleImpl!(Color.lightRed);
public alias lightGreen   = StyleImpl!(Color.lightGreen);
public alias lightYellow  = StyleImpl!(Color.lightYellow);
public alias lightBlue    = StyleImpl!(Color.lightBlue);
public alias lightMagenta = StyleImpl!(Color.lightMagenta);
public alias lightCyan    = StyleImpl!(Color.lightCyan);
public alias white        = StyleImpl!(Color.white);

public alias onBlack        = StyleImpl!(colorBgOffset + Color.black);
public alias onRed          = StyleImpl!(colorBgOffset + Color.red);
public alias onGreen        = StyleImpl!(colorBgOffset + Color.green);
public alias onYellow       = StyleImpl!(colorBgOffset + Color.yellow);
public alias onBlue         = StyleImpl!(colorBgOffset + Color.blue);
public alias onMagenta      = StyleImpl!(colorBgOffset + Color.magenta);
public alias onCyan         = StyleImpl!(colorBgOffset + Color.cyan);
public alias onLightGray    = StyleImpl!(colorBgOffset + Color.lightGray);
public alias onDarkGray     = StyleImpl!(colorBgOffset + Color.darkGray);
public alias onLightRed     = StyleImpl!(colorBgOffset + Color.lightRed);
public alias onLightGreen   = StyleImpl!(colorBgOffset + Color.lightGreen);
public alias onLightYellow  = StyleImpl!(colorBgOffset + Color.lightYellow);
public alias onLightBlue    = StyleImpl!(colorBgOffset + Color.lightBlue);
public alias onLightMagenta = StyleImpl!(colorBgOffset + Color.lightMagenta);
public alias onLightCyan    = StyleImpl!(colorBgOffset + Color.lightCyan);
public alias onWhite        = StyleImpl!(colorBgOffset + Color.white);


nothrow pure @safe unittest
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

nothrow pure @safe @nogc unittest
{
    auto style = bold;
    style = italic; // Should be able to reassign.
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
    Split a string into two parts: `result[0]` (head) is the first textual chunk (i.e., with no command sequences) that
    occurs in `text`; `result[1]` (tail) is everything that follows it, with one leading command sequence stripped.
 */
private inout(char)[][2] findNextTextChunk(return scope inout(char)[] text) nothrow pure @safe @nogc
{
    import std.ascii: isDigit;
    import std.string: indexOf;

    static assert(separator.length == 1);
    static assert(suffix.length == 1);

    size_t idx = 0;

    while(true)
    {
        immutable seqIdx = text.indexOf(prefix, idx);

        if(seqIdx < 0)
            return [text, null];

        idx = seqIdx + prefix.length;
        while(idx < text.length && (text[idx] == separator[0] || isDigit(text[idx])))
            idx++;

        if(idx < text.length && text[idx] == suffix[0])
        {
            idx++;
            if(seqIdx > 0) // If the chunk is not empty
                return [text[0 .. seqIdx], text[idx .. $]];

            // Chunk is empty so we skip command sequence and continue
            text = text[idx .. $];
            idx = 0;
        }
    }
}

public auto getUnstyledText(C : char)(return scope C[] text)
{
    struct Unstyler
    {
        private C[] head, tail;

        @property bool empty() const { return head.length == 0; }

        @property inout(C)[] front() inout { return head; }

        void popFront()
        {
            auto a = findNextTextChunk(tail);
            head = a[0];
            tail = a[1];
        }

        @property auto save() inout { return this; }
    }

    auto a = findNextTextChunk(text);
    return Unstyler(a[0], a[1]);
}

nothrow pure @safe @nogc unittest
{
    import std.range.primitives: ElementType, isForwardRange;

    alias R = typeof(getUnstyledText(""));
    assert(isForwardRange!R);
    assert(is(ElementType!R == string));
}

nothrow pure @safe @nogc unittest
{
    bool eq(T)(T actual, const(char[])[] expected...) // This allows `expected` to be `@nogc` even without `-dip1000`
    {
        import std.algorithm.comparison: equal;

        return equal(actual, expected);
    }

    assert(eq(getUnstyledText("")));
    assert(eq(getUnstyledText("\x1b[m")));
    assert(eq(getUnstyledText("a\x1b[m"), "a"));
    assert(eq(getUnstyledText("a\x1b[0;1m\x1b[9mm\x1b[m\x1b["), "a", "m", "\x1b["));
    assert(eq(getUnstyledText("a\x1b[0:abc\x1b[m"), "a\x1b[0:abc"));

    char[2] m = "\x1b[";
    const char[2] c = "\x1b[";
    immutable char[2] i = "\x1b[";

    assert(eq(getUnstyledText(m), "\x1b["));
    assert(eq(getUnstyledText(c), "\x1b["));
    assert(eq(getUnstyledText(i), "\x1b["));
}

package size_t getUnstyledTextLength(string text)
{
    import std.algorithm: map, sum;

    return text.getUnstyledText.map!(_ => _.length).sum;
}

package size_t getUnstyledTextLength(StyledText text)
{
    return getUnstyledTextLength(text.text);
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

private enum STREAM { STDOUT, STDERR }

package alias STDOUT = STREAM.STDOUT;
package alias STDERR = STREAM.STDERR;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package bool detectSupport(STREAM stream)
{
    // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    // Heuristics section in README must be in sync with the code below
    // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

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
        import core.sys.windows.winbase: GetStdHandle, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE, INVALID_HANDLE_VALUE;
        import core.sys.windows.wincon: GetConsoleMode, SetConsoleMode, ENABLE_VIRTUAL_TERMINAL_PROCESSING;

        auto handle = GetStdHandle(stream == STDOUT ? STD_OUTPUT_HANDLE : STD_ERROR_HANDLE);
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
        import core.sys.posix.unistd: isatty, STDOUT_FILENO, STDERR_FILENO;
        return isatty(stream == STDOUT ? STDOUT_FILENO : STDERR_FILENO) == 1;
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

        return detectSupport(STDOUT);
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
    auto defaultVal = detectSupport(STDOUT);
    assert(detect("CLICOLOR","1") == defaultVal);
    assert(detect("ConEmuANSI","") == defaultVal);
    assert(detect("CLICOLOR_FORCE","0") == defaultVal);

    version(Windows)
    {
        environment.remove("TERM");

        assert(!detectSupport(STDOUT));

        environment["TERM"] = "some cygwin flavor";
        assert(detectSupport(STDOUT));

        environment["TERM"] = "xterm1";
        assert(detectSupport(STDOUT));
    }
}