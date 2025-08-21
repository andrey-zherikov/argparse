module argparse.api.cli;

import argparse.config;
import argparse.result;
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

private void onError(Config config, alias printer = defaultErrorPrinter)(string message) nothrow
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

    assert(collectExceptionMsg!Error(onError!(Config.init, printer)("text")) == "My Message.");
}

unittest
{
    enum config = {
        Config config;
        config.errorHandler = (string s) { assert(s == "error text"); };
        return config;
    }();

    onError!config("error text");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Public API for CLI wrapper
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

template CLI(Config config, COMMANDS...)
{
    template main(alias newMain)
    {
        import argparse.api.subcommand: SubCommand, match;

        private struct Program
        {
            SubCommand!COMMANDS cmd;   // Sub-commands
        }

        private static auto forwardMain(Args...)(Program prog, auto ref Args args)
        {
            import core.lifetime: forward;
            return prog.cmd.match!(_ => newMain(_, forward!args));
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

        if(!res)
            onError!config(res.errorMessage);

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
            res = Result.Error(config.errorExitCode, "Unrecognized arguments: ", args);
            onError!config(res.errorMessage);
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
        import argparse.api.subcommand: match;

        Complete!COMMAND comp;

        // We are able to instantiate `CLI` with different arguments solely because we reside in a templated function.
        // If we weren't, that would lead to infinite template recursion.
        auto res = CLI!(config, Complete!COMMAND).parseArgs(comp, args);
        if (!res)
            return res.exitCode;

        comp.cmd.match!(_ => _.execute!(config, COMMAND));

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

                if (!res)
                    return res.exitCode;

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
    // If this unit test is removed then dmd fails with this:
    //   fatal error LNK1103: debugging information corrupt; recompile module
    //   Error: linker exited with status 1103
    struct T
    {
        enum Fruit { apple, pear };

        Fruit a;
    }

    T t;
    assert(CLI!T.parseArgs(t, ["-a", "apple"]));
}
