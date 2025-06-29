module argparse.api.cli;

import argparse.config;
import argparse.result;
import argparse.api.ansi: ansiStylingArgument;
import argparse.ansi: getUnstyledText;
import argparse.internal.parser: callParser;
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
            if(ansiStylingArgument)
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
        auto res = callParser!(config, false)(receiver, args, unrecognizedArgs);

        if(!res && res.errorMsg.length > 0)
            onError!config(res.errorMsg);

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
            res = Result.Error("Unrecognized arguments: ", args);
            onError!config(res.errorMsg);
        }

        return res;
    }

    // This is a template to avoid compiling it unless it is actually used.
    string[] completeArgs()(string[] args)
    {
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

    template main(alias newMain)
    {
        version(argparse_completion)
        {
            mixin CLI!(config, COMMAND).mainComplete;
        }
        else
        {
            int main(string[] argv)
            {
                static if (is(typeof(newMain!COMMAND)))
                    return CLI!(config, COMMAND).parseArgs(argv[1..$], newMain!COMMAND);
                else
                    return CLI!(config, COMMAND).parseArgs(argv[1..$], newMain!(COMMAND, string[]));
            }
        }
    }

    template main1(alias newMain)
    {
        int main1(string[] argv)
        {
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

alias CLI(COMMANDS...) = CLI!(Config.init, COMMANDS);

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    static struct Args {}

    Args initValue;

    enum Config cfg = { errorHandler: (string s) {} };

    assert(CLI!(cfg, Args).parseArgs([], (cmd      ) {}) == 0);
    assert(CLI!(cfg, Args).parseArgs([], (cmd, args) {}) == 0);
    assert(CLI!(cfg, Args).parseArgs([], (cmd      ) => 123) == 123);
    assert(CLI!(cfg, Args).parseArgs([], (cmd, args) => 123) == 123);

    assert(CLI!(cfg, Args).parseArgs([], (cmd      ) {}, initValue) == 0);
    assert(CLI!(cfg, Args).parseArgs([], (cmd, args) {}, initValue) == 0);
    assert(CLI!(cfg, Args).parseArgs([], (cmd      ) => 123, initValue) == 123);
    assert(CLI!(cfg, Args).parseArgs([], (cmd, args) => 123, initValue) == 123);

    // Ensure that CLI.main is compilable
    { mixin CLI!(cfg, Args).main!((_                  ){}); }
    { mixin CLI!(cfg, Args).main!((_, string[] unknown){}); }
    { mixin CLI!(cfg, Args).main!((_                  ){ return 123; }); }
    { mixin CLI!(cfg, Args).main!((_, string[] unknown){ return 123; }); }
}

// Ensure that CLI works with non-copyable structs
unittest
{
    static struct Args {
        this(int) {}
    }

    //Args initValue;
    auto initValue = Args(0);

    enum Config cfg = { errorHandler: (string s) {} };

    assert(CLI!(cfg, Args).parseArgs([], (ref _                  ){}) == 0);
    assert(CLI!(cfg, Args).parseArgs([], (ref _, string[] unknown){}) == 0);
    assert(CLI!(cfg, Args).parseArgs([], (ref _                  ){ return 123; }) == 123);
    assert(CLI!(cfg, Args).parseArgs([], (ref _, string[] unknown){ return 123; }) == 123);

    assert(CLI!(cfg, Args).parseArgs([], (ref _                  ){}, initValue) == 0);
    assert(CLI!(cfg, Args).parseArgs([], (ref _, string[] unknown){}, initValue) == 0);
    assert(CLI!(cfg, Args).parseArgs([], (ref _                  ){ return 123; }, initValue) == 123);
    assert(CLI!(cfg, Args).parseArgs([], (ref _, string[] unknown){ return 123; }, initValue) == 123);

    // Ensure that CLI.main is compilable
    { mixin CLI!(cfg, Args).main!((ref _                  ){}); }
    { mixin CLI!(cfg, Args).main!((ref _, string[] unknown){}); }
    { mixin CLI!(cfg, Args).main!((ref _                  ){ return 123; }); }
    { mixin CLI!(cfg, Args).main!((ref _, string[] unknown){ return 123; }); }
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
