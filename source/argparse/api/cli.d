module argparse.api.cli;

import argparse.config;
import argparse.helpinfo: CommandHelpInfo;
import argparse.helpprinter: HelpPrinter;
import argparse.result;
import argparse.style: Style;
import argparse.api.ansi: ansiStylingArgument;
import argparse.ansi: getUnstyledText;
import argparse.internal.parser: parseArgs;
import argparse.internal.completer: completeArgs, Complete;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Private helper for error output

private void defaultErrorPrinter(T...)(T message)
{
    import std.stdio: stderr, writeln;

    stderr.writeln(message);
}

private void onError(alias printer = defaultErrorPrinter)(Config config, string message) nothrow
{
    import std.algorithm.iteration: joiner;

    if(config.errorHandler)
        config.errorHandler(message);
    else
        try
        {
            if(ansiStylingArgument.stderrStyling)
                printer(config.styling.errorMessagePrefix("Error: "), message);
            else
                printer("Error: ", message.getUnstyledText.joiner);
        }
        catch(Exception e)
        {
            throw new Error(e.msg);
        }
}

unittest
{
    import std.exception;

    static void printer(T...)(T m)
    {
        throw new Exception("My Message.");
    }

    assert(collectExceptionMsg!Error(onError!printer(Config.init, "text")) == "My Message.");
}

unittest
{
    enum Config config = { errorHandler: s => assert(s == "error text") };

    onError(config, "error text");
}

// Prints what accompanies an error message, as selected by Config.helpOnError.
//
// Config.helpPrinter is consulted for `full` only: that hook renders the help screen, which is what `full`
// prints, whereas `usage` prints the short "Usage: ..." line that conventionally precedes an error and has no
// corresponding hook.
private void onErrorHelp(alias printer = defaultErrorPrinter)(Config config, CommandHelpInfo[] cmds) nothrow
{
    import std.algorithm.iteration: map;
    import std.array: array;

    // Bail out before creating the style and the help printer: nothing below is needed to print nothing
    if(config.helpOnError == Config.HelpOnError.none || cmds.length == 0)
        return;

    try
    {
        auto style = ansiStylingArgument.stderrStyling ? config.styling : Style.None;

        scope hp = new HelpPrinter(config, style);

        final switch(config.helpOnError)
        {
            case Config.HelpOnError.none:
                assert(false);  // returned above

            case Config.HelpOnError.usage:
                // The usage line is built for the command that was being parsed (the last one in the stack)
                // and it is prefixed with the names of all the commands that lead to it.
                printer(hp.formatCommandUsage(cmds.map!((ref _) => _.name).array, cmds[$-1]));
                break;

            case Config.HelpOnError.full:
                if(config.helpPrinter)
                    config.helpPrinter(config, style, cmds);
                else
                {
                    import std.stdio: stderr;

                    scope auto output = stderr.lockingTextWriter();

                    hp.printHelp(_ => output.put(_), cmds);
                }
                break;
        }
    }
    catch(Exception e)
    {
        throw new Error(e.msg);
    }
}

unittest
{
    static string printed;
    static void printer(T...)(T m)
    {
        import std.conv: text;

        printed = text(m);
    }

    auto cmds = [CommandHelpInfo(name: "prog"), CommandHelpInfo(name: "sub")];

    static assert(Config.init.helpOnError == Config.HelpOnError.none);   // default

    {
        enum Config config = {
            helpOnError: Config.HelpOnError.usage,
            stylingMode: Config.StylingMode.off,
        };

        // No help info attached => nothing is printed
        printed = null;
        onErrorHelp!printer(config, []);
        assert(printed is null);

        // Usage line of the whole command stack
        printed = null;
        onErrorHelp!printer(config, cmds);
        assert(printed == "Usage: prog sub");
    }
    {
        enum Config config = { helpOnError: Config.HelpOnError.none };

        printed = null;
        onErrorHelp!printer(config, cmds);
        assert(printed is null);
    }
    {
        // `full` renders the help screen, so it goes through Config.helpPrinter when one is provided
        enum Config config = {
            helpOnError: Config.HelpOnError.full,
            helpPrinter: (cfg, style, c) { assert(c.length == 2 && c[$-1].name == "sub"); },
        };

        printed = null;
        onErrorHelp!printer(config, cmds);
        assert(printed is null);   // the printer is not used by `full`
    }
    {
        // ... and it renders the help screen to stderr when no Config.helpPrinter is provided
        enum Config config = {
            helpOnError: Config.HelpOnError.full,
            stylingMode: Config.StylingMode.off,
        };

        printed = null;
        onErrorHelp!printer(config, cmds);
        assert(printed is null);   // the printer is not used by `full`
    }
}

unittest
{
    import std.exception;

    static void printer(T...)(T m)
    {
        throw new Exception("My Message.");
    }

    enum Config config = {
        helpOnError: Config.HelpOnError.usage,
        stylingMode: Config.StylingMode.off,
    };

    auto cmds = [CommandHelpInfo(name: "prog")];

    assert(collectExceptionMsg!Error(onErrorHelp!printer(config, cmds)) == "My Message.");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Public API for CLI wrapper
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

template CLI(Config config, COMMANDS...)
{
    template main(alias newMain)
    {
        import argparse.api.subcommand: SubCommand, matchCmd;

        private struct Program
        {
            SubCommand!COMMANDS cmd;   // Sub-commands
        }

        private static auto forwardMain(Args...)(Program prog, auto ref Args args)
        {
            import core.lifetime: forward;
            return prog.cmd.matchCmd!(_ => newMain(_, forward!args));
        }

        mixin CLI!(config, Program).main!forwardMain;
    }
}

template CLI(Config config, COMMAND)
{
    static Result parseKnownArgs(ref COMMAND receiver, string[] args, out string[] unrecognizedArgs)
    {
        ansiStylingArgument.initialize(config.stylingMode);

        auto res = .parseArgs!config(receiver, args, unrecognizedArgs);

        if(res.isError)
        {
            static if(config.helpOnError != Config.HelpOnError.none)
                onErrorHelp(config, res.cmdHelpInfo);

            onError(config, res.errorMessage);
        }

        return res;
    }

    static Result parseKnownArgs(ref COMMAND receiver, ref string[] args)
    {
        string[] unrecognizedArgs;

        auto res = parseKnownArgs(receiver, args, unrecognizedArgs);
        if(res)
            args = unrecognizedArgs;

        return res;
    }

    static Result parseArgs(ref COMMAND receiver, string[] args)
    {
        auto res = parseKnownArgs(receiver, args);
        if(res && args.length > 0)
        {
            // Parsing itself succeeded, so the help info is carried by the successful result: move it onto
            // the error that replaces it, otherwise the command that was being parsed would be lost here.
            auto cmdHelpInfo = res.cmdHelpInfo;

            res = Result.Error(config.errorExitCode, "Unrecognized arguments: ", args);
            res.cmdHelpInfo = cmdHelpInfo;

            static if(config.helpOnError != Config.HelpOnError.none)
                onErrorHelp(config, res.cmdHelpInfo);

            onError(config, res.errorMessage);
        }

        return res;
    }

    // This is a template to avoid compiling it unless it is actually used.
    string[] completeArgs()(string[] args)
    {
        ansiStylingArgument.initialize(config.stylingMode);

        return .completeArgs!(config, COMMAND)(args);
    }

    // This is a template to avoid compiling it unless it is actually used.
    int complete()(string[] args)
    {
        import argparse.api.subcommand: matchCmd;

        Complete!COMMAND comp;

        // We are able to instantiate `CLI` with different arguments solely because we reside in a templated function.
        // If we weren't, that would lead to infinite template recursion.
        auto res = CLI!(config, Complete!COMMAND).parseArgs(comp, args);
        if (!res)
            return res.exitCode;

        comp.cmd.matchCmd!(_ => _.execute!(config, COMMAND));

        return 0;
    }

    template mainComplete()
    {
        int main(string[] argv)
        {
            return CLI!(config, COMMAND).complete(argv[1..$]);
        }
    }

    version(argparse_completion)
    {
        template main(alias newMain)
        {
            mixin CLI!(config, COMMAND).mainComplete;
        }
    }
    else
    {
        template main(alias newMain)
        {
            int main(string[] argv)
            {
                argv = argv[1..$];
                static if(is(COMMAND == class))
                    auto value = new COMMAND;
                else
                    COMMAND value;

                static if (is(typeof(newMain(value, argv))))
                {
                    // newMain has two parameters so parse only known arguments
                    auto res = CLI!(config, COMMAND).parseKnownArgs(value, argv);
                }
                else
                {
                    // Assume newMain has one parameter, so strictly parse command line
                    auto res = CLI!(config, COMMAND).parseArgs(value, argv);
                }

                if(res.isError)
                    return res.exitCode;
                else if(res.isHelpWanted)
                    return 0;

                // call newMain
                static if (is(typeof(newMain(value, argv)) == void))
                {
                    newMain(value, argv);
                    return 0;
                }
                else static if (is(typeof(newMain(value, argv))))
                {
                    return newMain(value, argv);
                }
                else static if (is(typeof(newMain(value)) == void))
                {
                    newMain(value);
                    return 0;
                }
                else
                {
                    return newMain(value);
                }
            }
        }
    }
}

alias CLI(COMMANDS...) = CLI!(Config.init, COMMANDS);

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    static struct Args {
        string s;
    }

    auto test(alias F)()
    {
        mixin CLI!Args.main!F;

        return main(["executable","-s","1"]); // argv[0] is executable
    }

    assert(test!(function(_){assert(_ == Args("1"));}) == 0);
    assert(test!(function(_){assert(_ == Args("1")); return 123;}) == 123);

    assert(test!(function(ref _){assert(_ == Args("1"));}) == 0);
    assert(test!(function(ref _){assert(_ == Args("1")); return 123;}) == 123);

    assert(test!(delegate(_){assert(_ == Args("1"));}) == 0);
    assert(test!(delegate(_){assert(_ == Args("1")); return 123;}) == 123);

    assert(test!(delegate(ref _){assert(_ == Args("1"));}) == 0);
    assert(test!(delegate(ref _){assert(_ == Args("1")); return 123;}) == 123);
}

unittest
{
    static struct Args {
        string s;
    }

    auto test(alias F)()
    {
        mixin CLI!Args.main!F;

        return main(["executable","-s","1","u"]); // argv[0] is executable
    }

    assert(test!(function(_, unknown){assert(_ == Args("1")); assert(unknown == ["u"]);}) == 0);
    assert(test!(function(_, unknown){assert(_ == Args("1")); assert(unknown == ["u"]); return 123;}) == 123);

    assert(test!(function(ref _, unknown){assert(_ == Args("1")); assert(unknown == ["u"]);}) == 0);
    assert(test!(function(ref _, unknown){assert(_ == Args("1")); assert(unknown == ["u"]); return 123;}) == 123);

    assert(test!(delegate(_, unknown){assert(_ == Args("1")); assert(unknown == ["u"]);}) == 0);
    assert(test!(delegate(_, unknown){assert(_ == Args("1")); assert(unknown == ["u"]); return 123;}) == 123);

    assert(test!(delegate(ref _, unknown){assert(_ == Args("1")); assert(unknown == ["u"]);}) == 0);
    assert(test!(delegate(ref _, unknown){assert(_ == Args("1")); assert(unknown == ["u"]); return 123;}) == 123);
}

unittest
{
    // Ensure that CLI.main works with non-copyable structs
    static struct Args {
        @disable this(ref Args);
        @disable void opAssign(ref Args);

        string s;
    }

    auto test(alias F)()
    {
        mixin CLI!Args.main!F;

        return main(["executable","-s","1"]); // argv[0] is executable
    }

    assert(test!(function(ref _){assert(_ == Args("1"));}) == 0);
    assert(test!(function(ref _){assert(_ == Args("1")); return 123;}) == 123);

    assert(test!(delegate(ref _){assert(_ == Args("1"));}) == 0);
    assert(test!(delegate(ref _){assert(_ == Args("1")); return 123;}) == 123);
}

unittest
{
    // Ensure that CLI.main works with non-copyable structs
    static struct Args {
        @disable this(ref Args);
        @disable void opAssign(ref Args);

        string s;
    }

    auto test(alias F)()
    {
        mixin CLI!Args.main!F;

        return main(["executable","-s","1","u"]); // argv[0] is executable
    }

    assert(test!(function(ref _, unknown){assert(_ == Args("1")); assert(unknown == ["u"]);}) == 0);
    assert(test!(function(ref _, unknown){assert(_ == Args("1")); assert(unknown == ["u"]); return 123;}) == 123);

    assert(test!(delegate(ref _, unknown){assert(_ == Args("1")); assert(unknown == ["u"]);}) == 0);
    assert(test!(delegate(ref _, unknown){assert(_ == Args("1")); assert(unknown == ["u"]); return 123;}) == 123);
}

unittest
{
    // Ensure that CLI.main works with classes
    static class Args {
        string s;
    }

    auto test(alias F)()
    {
        mixin CLI!Args.main!F;

        return main(["executable","-s","1","u"]); // argv[0] is executable
    }

    assert(test!(function(ref _, unknown){assert(_.s == "1"); assert(unknown == ["u"]);}) == 0);
    assert(test!(function(ref _, unknown){assert(_.s == "1"); assert(unknown == ["u"]); return 123;}) == 123);

    assert(test!(delegate(ref _, unknown){assert(_.s == "1"); assert(unknown == ["u"]);}) == 0);
    assert(test!(delegate(ref _, unknown){assert(_.s == "1"); assert(unknown == ["u"]); return 123;}) == 123);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    struct T
    {
        string[] a;
        string[][]  b;
    }

    enum Config config = { variadicNamedArgument: true };

    auto test(string[] args)
    {
        T t;
        assert(CLI!(config, T).parseArgs(t, args));
        return t;
    }

    assert(test(["-a","1","2","3","-a","4","5"]).a == ["1","2","3","4","5"]);
    assert(test(["-a=1,2,3","-a","4","5"]).a == ["1","2","3","4","5"]);
    assert(test(["-a","1,2,3","-a","4","5"]).a == ["1,2,3","4","5"]);
    assert(test(["-b","1","2","3","-b","4","5"]).b == [["1","2","3"],["4","5"]]);
}

unittest
{
    struct T
    {
        int[string] a;
    }

    auto test(Config config = Config.init)(string[] args)
    {
        T t;
        assert(CLI!(config, T).parseArgs(t, args));
        return t;
    }

    assert(test(["-a=foo=3","-a","boo=7"]) == T(["foo":3,"boo":7]));
    assert(test(["-a=foo=3,boo=7"]) == T(["foo":3,"boo":7]));

    enum Config config = { variadicNamedArgument: true };

    assert(test!config(["-a","foo=3","boo=7"])== T(["foo":3,"boo":7]));
}

unittest
{
    struct T
    {
        enum Fruit { apple, pear };

        Fruit a;
    }

    auto test(string[] args)
    {
        T t;
        assert(CLI!T.parseArgs(t, args));
        return t;
    }

    assert(test(["-a","apple"]) == T(T.Fruit.apple));
    assert(test(["-a=pear"]) == T(T.Fruit.pear));

    T t;
    assert(CLI!T.parseArgs(t, ["-a", "kiwi"]).isError("Invalid value","kiwi"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    struct T
    {
        string x;
        string foo;
    }

    enum Config config = { caseSensitiveShortName: false, caseSensitiveLongName: false, caseSensitiveSubCommand: false };

    auto test(string[] args)
    {
        T t;
        assert(CLI!(config, T).parseArgs(t, args));
        return t;
    }


    assert(test(["--Foo","FOO","-X","X"]) == T("X", "FOO"));
    assert(test(["--FOo=FOO","-X=X"]) == T("X", "FOO"));
}

unittest
{
    struct T
    {
        bool a;
        bool b;
        string c;
    }
    enum Config config = { bundling: true };

    auto test(string[] args)
    {
        T t;
        assert(CLI!(config, T).parseArgs(t, args));
        return t;
    }

    assert(test(["-a","-b"])            == T(true, true));
    assert(test(["-ab"])                == T(true, true));
    assert(test(["-abc=foo"])           == T(true, true, "foo"));
    assert(test(["-a","-bc=foo"])       == T(true, true, "foo"));
    assert(test(["-a","-bcfoo"])        == T(true, true, "foo"));
    assert(test(["-a","-b","-cfoo"])    == T(true, true, "foo"));
    assert(test(["-a","-b","-c=foo"])   == T(true, true, "foo"));
    assert(test(["-a","-b","-c","foo"]) == T(true, true, "foo"));
}

unittest
{
    struct T
    {
        string c;
    }

    auto test(string[] args)
    {
        T t;
        assert(CLI!T.parseArgs(t, args));
        return t;
    }

    assert(test(["-c","foo"]) == T("foo"));
    assert(test(["-c=foo"])   == T("foo"));
    assert(test(["-cfoo"])    == T("foo"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    struct T
    {
        static auto color = ansiStylingArgument;
    }

    T t;

    assert(CLI!T.parseArgs(t, ["--color"]));
    assert(t.color);
    assert(CLI!T.parseArgs(t, ["--color","never"]));
    assert(!t.color);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    // https://github.com/andrey-zherikov/argparse/issues/246
    struct T {}

    enum Config config = { errorHandler: _ => assert(false) };

    T t;
    assert(CLI!(config, T).parseArgs(t, ["-h"]).isHelpWanted);
    assert(CLI!(config, T).parseArgs(t, ["--help"]).isHelpWanted);

    auto test_main(string[] args)
    {
        mixin CLI!T.main!(_ => assert(false));

        return main(args);
    }

    assert(test_main(["executable","-h"]) == 0);// argv[0] is executable
    assert(test_main(["executable","--help"]) == 0);// argv[0] is executable
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Config.helpOnError

version(unittest)
{
    // Names of the commands that whatever is printed on error is built from, i.e. what `onErrorHelp` receives
    private string[] helpOnErrorCommandNames(Result res)
    {
        import std.algorithm.iteration: map;
        import std.array: array;

        return res.cmdHelpInfo.map!((ref _) => _.name).array;
    }
}

unittest
{
    import argparse.api.argument;

    struct T
    {
        @(NamedArgument.Required) string s;
    }

    // `usage` and `full` both need the help info, `none` doesn't
    static foreach(mode; [Config.HelpOnError.usage, Config.HelpOnError.full])
    {{
        enum Config config = {
            helpOnError: mode,
            stylingMode: Config.StylingMode.off,
            helpPrinter: (cfg, style, cmds) { },
            errorHandler: (msg) { },
        };

        T t;

        auto res = CLI!(config, T).parseArgs(t, []);
        assert(res.isError("The following argument is required"));
        assert(res.helpOnErrorCommandNames.length == 1);

        // Nothing is printed when parsing succeeds, but the help info is still carried by the result so that
        // errors detected afterwards (unrecognized arguments) can be reported against the right command
        assert(CLI!(config, T).parseArgs(t, ["-s","S"]).helpOnErrorCommandNames.length == 1);
    }}

    {
        enum Config config = {
            helpOnError: Config.HelpOnError.none,
            stylingMode: Config.StylingMode.off,
            helpPrinter: (cfg, style, cmds) => assert(false),
            errorHandler: (msg) { },
        };

        T t;
        assert(CLI!(config, T).parseArgs(t, []).isError("The following argument is required"));
        assert(CLI!(config, T).parseArgs(t, ["-s","S","extra"]).isError("Unrecognized arguments"));

        // `none` must not compute the help info at all
        string[] unrecognizedArgs;
        assert(.parseArgs!config(t, [], unrecognizedArgs).cmdHelpInfo.length == 0);
    }
}

unittest
{
    import argparse.api.argument;
    import argparse.api.command: Command;
    import argparse.api.subcommand: SubCommand;

    // Whatever is printed belongs to the command that was actually being parsed, not to the top level one
    struct sub
    {
        @(NamedArgument.Required) string req;
    }

    @(Command("prog"))
    struct T
    {
        SubCommand!sub cmd;
    }

    enum Config config = {
        helpOnError: Config.HelpOnError.usage,
        stylingMode: Config.StylingMode.off,
        errorHandler: (msg) { },
    };

    T t;

    // Error raised while parsing the subcommand
    assert(CLI!(config, T).parseArgs(t, ["sub"]).helpOnErrorCommandNames == ["prog","sub"]);

    // Unrecognized arguments are detected once parsing succeeded, so this only works because a successful
    // result carries the help info as well
    assert(CLI!(config, T).parseArgs(t, ["sub","--req","R","extra"]).helpOnErrorCommandNames == ["prog","sub"]);

    // Top level error still reports the top level command
    assert(CLI!(config, T).parseArgs(t, ["extra"]).helpOnErrorCommandNames == ["prog"]);
}
