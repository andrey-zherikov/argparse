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

    static int parseArgs(alias newMain)(string[] args, auto ref COMMAND initialValue = COMMAND.init)
    if(__traits(compiles, { newMain(initialValue); }))
    {
        alias value = initialValue;

        auto res = parseArgs(value, args);
        if(!res)
            return res.exitCode;

        static if(__traits(compiles, { int a = cast(int) newMain(value); }))
            return cast(int) newMain(value);
        else
        {
            newMain(value);
            return 0;
        }
    }

    static int parseArgs(alias newMain)(string[] args, auto ref COMMAND initialValue = COMMAND.init)
    if(__traits(compiles, { newMain(initialValue, string[].init); }))
    {
        alias value = initialValue;

        auto res = parseKnownArgs(value, args);
        if(!res)
            return res.exitCode;

        static if(__traits(compiles, { int a = cast(int) newMain(value, args); }))
            return cast(int) newMain(value, args);
        else
        {
            newMain(value, args);
            return 0;
        }
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

        // We are able to instantiate `CLI` with different arguments solely because we reside in a templated function.
        // If we weren't, that would lead to infinite template recursion.
        return CLI!(config, Complete!COMMAND).parseArgs!(comp =>
            comp.cmd.match!(_ => _.execute!(config, COMMAND))
        )(args);
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
                return CLI!(config, COMMAND).parseArgs!(newMain)(argv[1..$]);
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

    assert(CLI!(cfg, Args).parseArgs!((_                  ){})([]) == 0);
    assert(CLI!(cfg, Args).parseArgs!((_, string[] unknown){})([]) == 0);
    assert(CLI!(cfg, Args).parseArgs!((_                  ){ return 123; })([]) == 123);
    assert(CLI!(cfg, Args).parseArgs!((_, string[] unknown){ return 123; })([]) == 123);

    assert(CLI!(cfg, Args).parseArgs!((_                  ){})([], initValue) == 0);
    assert(CLI!(cfg, Args).parseArgs!((_, string[] unknown){})([], initValue) == 0);
    assert(CLI!(cfg, Args).parseArgs!((_                  ){ return 123; })([], initValue) == 123);
    assert(CLI!(cfg, Args).parseArgs!((_, string[] unknown){ return 123; })([], initValue) == 123);

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
        @disable this(ref Args);
        this(int) {}
    }

    //Args initValue;
    auto initValue = Args(0);

    enum Config cfg = { errorHandler: (string s) {} };

    assert(CLI!(cfg, Args).parseArgs!((ref _                  ){})([]) == 0);
    assert(CLI!(cfg, Args).parseArgs!((ref _, string[] unknown){})([]) == 0);
    assert(CLI!(cfg, Args).parseArgs!((ref _                  ){ return 123; })([]) == 123);
    assert(CLI!(cfg, Args).parseArgs!((ref _, string[] unknown){ return 123; })([]) == 123);

    assert(CLI!(cfg, Args).parseArgs!((ref _                  ){})([], initValue) == 0);
    assert(CLI!(cfg, Args).parseArgs!((ref _, string[] unknown){})([], initValue) == 0);
    assert(CLI!(cfg, Args).parseArgs!((ref _                  ){ return 123; })([], initValue) == 123);
    assert(CLI!(cfg, Args).parseArgs!((ref _, string[] unknown){ return 123; })([], initValue) == 123);

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

    assert(CLI!T.parseArgs!((T t) { assert(false); })(["-a", "kiwi"]) != 0);    // "kiwi" is not allowed
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
        string a;
        static auto color = ansiStylingArgument;
    }

    assert(CLI!T.parseArgs!((T t) { assert(false); })(["-g"]) != 0);
    assert(CLI!T.parseArgs!((T t) { assert(t == T.init); return 12345; })([]) == 12345);
    assert(CLI!T.parseArgs!((T t, string[] args) {
        assert(t == T.init);
        assert(args.length == 0);
        return 12345;
    })([]) == 12345);
    assert(CLI!T.parseArgs!((T t, string[] args) {
        assert(t == T("aa"));
        assert(args == ["-g"]);
        return 12345;
    })(["-a","aa","-g"]) == 12345);
    assert(CLI!T.parseArgs!((T t) {
        assert(t.color);
        return 12345;
    })(["--color"]) == 12345);
    assert(CLI!T.parseArgs!((T t) {
        assert(!t.color);
        return 12345;
    })(["--color","never"]) == 12345);
}

unittest
{
    struct T
    {
        string a;
        string b;
    }

    assert(CLI!T.parseArgs!((T t, string[] args) {
        assert(t == T("A"));
        assert(args == []);
        return 12345;
    })(["-a","A","--"]) == 12345);

    {
        T args;

        assert(CLI!T.parseArgs(args, [ "-a", "A"]));
        assert(CLI!T.parseArgs(args, [ "-b", "B"]));

        assert(args == T("A","B"));
    }
}

unittest
{
    struct T
    {
        string a;
    }

    import std.exception;

    assert(collectExceptionMsg(
        CLI!T.parseArgs!((T t, string[] args) {
            assert(t == T.init);
            assert(args.length == 0);
            throw new Exception("My Message.");
        })([]))
    == "My Message.");
    assert(collectExceptionMsg(
        CLI!T.parseArgs!((T t, string[] args) {
            assert(t == T("aa"));
            assert(args == ["-g"]);
            throw new Exception("My Message.");
        })(["-a","aa","-g"]))
    == "My Message.");
    assert(CLI!T.parseArgs!((T t, string[] args) {
        assert(t == T.init);
        assert(args.length == 0);
    })([]) == 0);
    assert(CLI!T.parseArgs!((T t, string[] args) {
        assert(t == T("aa"));
        assert(args == ["-g"]);
    })(["-a","aa","-g"]) == 0);
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
