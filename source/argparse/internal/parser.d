module argparse.internal.parser;

import std.typecons: Nullable, nullable;
import std.sumtype: SumType;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.api.ansi: ansiStylingArgument;
import argparse.internal.arguments: ArgumentInfo;
import argparse.internal.command: Command, createCommand;
import argparse.internal.commandinfo: getTopLevelCommandInfo;
import argparse.internal.commandstack;
import argparse.internal.tokenizer;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private struct Parser
{
    Config config;
    CommandStack* cmdStack;

    string[] unrecognizedArgs;

    ///////////////////////////////////////////////////////////////////////

    auto parseAll(bool completionMode)(string[] args)
    {
        import std.sumtype : match;

        static if(completionMode)
        {
            auto tok = Tokenizer(config, args[0..$-1], cmdStack);

            foreach(entry; tok)
            {
                entry
                    .match!(
                        (ref SubCommand c) { cmdStack.addCommand(c.cmdInit()); },
                        (ref _) {}
                );
            }

            // Provide suggestions for the last argument only
            auto res = Result.Success;
            res.suggestions = cmdStack.getSuggestions(args[$-1]);
            return res;
        }
        else
        {
            auto tok = Tokenizer(config, args, cmdStack);

            foreach(entry; tok)
            {
                auto res = entry
                    .match!(
                        (Argument a) => a.parse(),
                        (ref SubCommand c) { cmdStack.addCommand(c.cmdInit()); return Result.Success; },
                        (ref Unknown u) { unrecognizedArgs ~= u.value; return Result.Success; }
                    );
                if (!res)
                    return res;
            }

            return cmdStack.checkRestrictions();
        }
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private Result callParser(bool completionMode)(
    Config config, Command cmd, string[] args, out string[] unrecognizedArgs,
)
{
    ansiStylingArgument.isEnabled = config.stylingMode == Config.StylingMode.on;

    CommandStack cmdStack;
    cmdStack.addCommand(cmd);

    Parser parser = { config, &cmdStack };

    auto res = parser.parseAll!completionMode(args);

    static if(!completionMode)
    {
        if(res)
            unrecognizedArgs = parser.unrecognizedArgs;
    }

    return res;
}

package(argparse) Result callParser(Config config, bool completionMode, COMMAND)(ref COMMAND receiver, string[] args, out string[] unrecognizedArgs)
if(config.stylingMode != Config.StylingMode.autodetect)
{
    return callParser!completionMode(
        config, createCommand!config(receiver, getTopLevelCommandInfo!COMMAND(config)), args, unrecognizedArgs,
    );
}

private auto enableStyling(Config config, bool enable)
{
    config.stylingMode = enable ? Config.StylingMode.on : Config.StylingMode.off;
    return config;
}

unittest
{
    assert(enableStyling(Config.init, true).stylingMode == Config.StylingMode.on);
    assert(enableStyling(Config.init, false).stylingMode == Config.StylingMode.off);
}

package(argparse) Result callParser(Config config, bool completionMode, COMMAND)(ref COMMAND receiver, string[] args, out string[] unrecognizedArgs)
if(config.stylingMode == Config.StylingMode.autodetect)
{
    import argparse.ansi: detectSupport;


    if(detectSupport())
        return callParser!(enableStyling(config, true), completionMode, COMMAND)(receiver, args, unrecognizedArgs);
    else
        return callParser!(enableStyling(config, false), completionMode, COMMAND)(receiver, args, unrecognizedArgs);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
unittest
{
    import argparse.api.argument;

    struct T
    {
        @(NamedArgument.NumberOfValues(2,4)) string[] f;
    }

    {
        enum Config config = { variadicNamedArgument: true };

        T t;
        string[] unrecognizedArgs;
        assert(callParser!(config, false)(t, ["-f", "a"], unrecognizedArgs).isError("Argument", "expected at least 2 values"));
        assert(callParser!(config, false)(t, ["-f", "a", "a"], unrecognizedArgs));
        assert(callParser!(config, false)(t, ["-f", "a", "a", "a"], unrecognizedArgs));
        assert(callParser!(config, false)(t, ["-f", "a", "a", "a", "a"], unrecognizedArgs));

        assert(unrecognizedArgs.length == 0);
        assert(callParser!(config, false)(t, ["-f", "a", "a", "a", "a", "a"], unrecognizedArgs));
        assert(unrecognizedArgs == ["a"]);
    }
    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(Config.init, false)(t, ["-f=a,a"], unrecognizedArgs));
        assert(callParser!(Config.init, false)(t, ["-f=a,a,a"], unrecognizedArgs));
        assert(callParser!(Config.init, false)(t, ["-f=a,a,a,a"], unrecognizedArgs));
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
unittest
{
    import argparse.api.argument: PositionalArgument, NamedArgument;

    struct T
    {
        @NamedArgument bool c;
        @PositionalArgument string fileName;
    }

    enum Config cfg = { stylingMode: Config.StylingMode.off };

    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(t, ["-", "-c"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(t == T(true, "-"));
    }
    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(t, ["-c", "-"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(t == T(true, "-"));
    }
    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(t, ["-"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(t == T(false, "-"));
    }
    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(t, ["-f","-"], unrecognizedArgs));
        assert(unrecognizedArgs == ["-f"]);
        assert(t == T(false, "-"));
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    struct T
    {
        string a;
        string baz;
    }

    enum Config cfg = { shortNamePrefix: "+", longNamePrefix: "==" };

    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(t, ["+a", "foo", "==baz", "BAZZ"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(t == T("foo", "BAZZ"));
    }
    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(t, ["+a", "foo", "++baz", "BAZZ"], unrecognizedArgs));
        assert(unrecognizedArgs == ["++baz", "BAZZ"]);
        assert(t == T("foo", ""));
    }
    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(t, ["=a", "foo", "==baz", "BAZZ"], unrecognizedArgs));
        assert(unrecognizedArgs == ["=a", "foo"]);
        assert(t == T("", "BAZZ"));
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    import argparse.api.argument;

    struct Args {
        @NamedArgument bool f;
        @PositionalArgument string[] files;
    }

    {
        Args args;
        string[] unrecognizedArgs;
        assert(callParser!(Config.init, false)(args, ["-f", "file1", "file2", "target"], unrecognizedArgs));
        assert(unrecognizedArgs == []);
        assert(args == Args(true,  ["file1", "file2", "target"]));
    }
    {
        Args args;
        string[] unrecognizedArgs;
        assert(callParser!(Config.init, false)(args, ["file1", "-f", "file2", "target"], unrecognizedArgs));
        import std.stdio;stderr.writeln(unrecognizedArgs, args);
        //assert(unrecognizedArgs == []);
        //assert(args == Args(true,  ["file1", "file2", "target"]));
    }
    {
        Args args;
        string[] unrecognizedArgs;
        assert(callParser!(Config.init, false)(args, ["file1", "file2", "-f", "target"], unrecognizedArgs));
        import std.stdio;stderr.writeln(unrecognizedArgs, args);
        //assert(unrecognizedArgs == []);
        //assert(args == Args(true,  ["file1", "file2", "target"]));
    }
    {
        Args args;
        string[] unrecognizedArgs;
        assert(callParser!(Config.init, false)(args, ["file1", "file2", "target", "-f"], unrecognizedArgs));
        assert(unrecognizedArgs == []);
        assert(args == Args(true,  ["file1", "file2", "target"]));
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    import argparse.api.subcommand: SubCommand;

    struct c1 {
        string foo;
        string boo;
    }
    struct cmd {
        string foo;
        SubCommand!(c1) c;
    }

    enum Config cfg = { stylingMode: Config.StylingMode.off };

    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--foo","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--boo","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs == ["--boo","BOO"]);
        assert(c == cmd.init);
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--foo","FOO","--boo","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs == ["--boo","BOO"]);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--boo","BOO","--foo","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs == ["--boo","BOO"]);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["c1","--boo","BOO","--foo","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("", typeof(c.c)(c1("FOO","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--foo","FOO","c1","--boo","BOO","--foo","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO"))));
    }
}

unittest
{
    import argparse.api.subcommand: Default, SubCommand;

    struct c1 {
        string foo;
        string boo;
    }
    struct cmd {
        string foo;
        SubCommand!(Default!c1) c;
    }

    enum Config cfg = { stylingMode: Config.StylingMode.off };

    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--foo","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--boo","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("", typeof(c.c)(c1("","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--foo","FOO","--boo","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--boo","BOO","--foo","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("", typeof(c.c)(c1("FOO","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["c1","--boo","BOO","--foo","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("", typeof(c.c)(c1("FOO","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--foo","FOO","c1","--boo","BOO","--foo","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO"))));
    }
}


unittest
{
    import argparse.api.argument;
    import argparse.api.subcommand: SubCommand;

    struct c1 {
        @PositionalArgument
        string foo;
        @(PositionalArgument.Optional)
        string boo;
    }
    struct cmd {
        @PositionalArgument
        string foo;

        SubCommand!(c1) c;
    }

    enum Config cfg = { stylingMode: Config.StylingMode.off };

    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs == ["FAA"]);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","--","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs == ["FAA"]);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs == ["FAA","BOO"]);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["c1","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs == ["FOO"]);
        assert(c == cmd("c1"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--","c1","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs == ["FOO"]);
        assert(c == cmd("c1"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","c1","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","c1","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","c1","--","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO"))));
    }
}


unittest
{
    import argparse.api.argument;
    import argparse.api.subcommand: Default, SubCommand;

    struct c1 {
        @PositionalArgument
        string foo;
        @(PositionalArgument.Optional)
        string boo;
    }
    struct cmd {
        @PositionalArgument
        string foo;

        SubCommand!(Default!c1) c;
    }

    enum Config cfg = { stylingMode: Config.StylingMode.off };

    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","--","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--","FOO","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["c1","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("c1", typeof(c.c)(c1("FOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","c1","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","c1","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","c1","--","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--","FOO","c1","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("c1","FAA"))));
    }
}


unittest
{
    import argparse.api.argument: PositionalArgument, NamedArgument;
    import argparse.api.subcommand: Default, SubCommand;

    struct c2 {
        @PositionalArgument
        string foo;
        @PositionalArgument
        string boo;
        @NamedArgument
        string bar;
    }
    struct c1 {
        @PositionalArgument
        string foo;
        @PositionalArgument
        string boo;

        SubCommand!(Default!c2) c;
    }
    struct cmd {
        @PositionalArgument
        string foo;

        SubCommand!(Default!c1) c;
    }

    enum Config cfg = { stylingMode: Config.StylingMode.off };

    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","FAA","BOO","FEE","BEE"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO", typeof(c1.c)(c2("FEE","BEE"))))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--bar","BAR","FOO","FAA","BOO","FEE","BEE"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO", typeof(c1.c)(c2("FEE","BEE","BAR"))))));
    }
}


unittest
{
    import argparse.api.argument: PositionalArgument, NamedArgument;
    import argparse.api.subcommand: Default, SubCommand;

    struct c2 {
        @PositionalArgument
        string foo;
        @PositionalArgument
        string boo;
        @NamedArgument
        string bar;
    }
    struct c1 {
        SubCommand!(Default!c2) c;
    }
    struct cmd {
        @PositionalArgument
        string foo;

        SubCommand!(Default!c1) c;
    }

    enum Config cfg = { stylingMode: Config.StylingMode.off };

    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1(typeof(c1.c)(c2("FAA","BOO"))))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--bar","BAR","FOO","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1(typeof(c1.c)(c2("FAA","BOO","BAR"))))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","c2","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1(typeof(c1.c)(c2("FAA","BOO"))))));
    }
}