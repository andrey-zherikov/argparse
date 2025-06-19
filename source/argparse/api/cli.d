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

    /**
     * Parse the arguments and call `newMain`, errors on unknown arguments
     *
     * This overload will parse the command line arguments in `args`, populate
     * a `COMMAND` struct based on `initialValue`, and then call `newMain`.
     *
     * Params:
     *   args = The CLI arguments as provided to `main`
     *   newMain = The main function to call if argument parsing is successful
     *   initialValue = An optional initial state for the `COMMAND` struct
     *
     * Returns:
     *   The return value of `newMain`, or `0` if `newMain` returns `void`.
     *   If any unrecognized argument is provided, returns a non-zero value.
     */
    static int parseArgs(string[] args, scope int delegate(ref COMMAND) newMain,
            auto ref COMMAND initialValue = COMMAND.init) {
        // For some reason the compiler tries to call the copy ctor despite our
        // use of auto-ref, so use its own overload to force `ref`
        return parseArgsFinal(args, newMain, initialValue);
    }

    /// Ditto
    private static int parseArgsFinal(string[] args,
        scope int delegate(ref COMMAND) newMain, ref COMMAND initialValue) {
        alias value = initialValue;
        auto res = parseArgs(value, args);
        if (!res)
            return res.exitCode;
        return newMain(value);
    }

    //// Ditto
    static int parseArgs(string[] args, scope void function(ref COMMAND) newMain,
            auto ref COMMAND initialValue = COMMAND.init) {
        return parseArgsFinal(args, (ref COMMAND cmd) { newMain(cmd); return 0; }, initialValue);
    }

    /// Ditto
    static int parseArgs(string[] args, scope void delegate(ref COMMAND) newMain,
            auto ref COMMAND initialValue = COMMAND.init) {
        return parseArgsFinal(args, (ref COMMAND cmd) { newMain(cmd); return 0; }, initialValue);
    }

    /// Ditto
    static int parseArgs(string[] args, scope int function(ref COMMAND) newMain,
            auto ref COMMAND initialValue = COMMAND.init) {
        return parseArgsFinal(args, (ref COMMAND cmd) => newMain(cmd), initialValue);
    }

    /// Ditto
    static int parseArgs(string[] args, scope int delegate(COMMAND) newMain,
            auto ref COMMAND initialValue = COMMAND.init) {
        return parseArgsFinal(args, (ref COMMAND cmd) => newMain(cmd), initialValue);
    }

    //// Ditto
    static int parseArgs(string[] args, scope void function(COMMAND) newMain,
            auto ref COMMAND initialValue = COMMAND.init) {
        return parseArgsFinal(args, (ref COMMAND cmd) { newMain(cmd); return 0; }, initialValue);
    }

    /// Ditto
    static int parseArgs(string[] args, scope void delegate(COMMAND) newMain,
            auto ref COMMAND initialValue = COMMAND.init) {
        return parseArgsFinal(args, (ref COMMAND cmd) { newMain(cmd); return 0; }, initialValue);
    }

    /// Ditto
    static int parseArgs(string[] args, scope int function(COMMAND) newMain,
            auto ref COMMAND initialValue = COMMAND.init) {
        return parseArgsFinal(args, (ref COMMAND cmd) => newMain(cmd), initialValue);
    }

    /**
     * Parse the arguments and call `newMain`, forwarding unknown arguments
     *
     * This overload will parse the command line arguments in `args`, populate
     * a `COMMAND` struct based on `initialValue`, and then call `newMain`
     * with the `COMMAND` as first argument and the remaining, unrecognized
     * arguments (if any) as second argument.
     *
     * Params:
     *   args = The CLI arguments as provided to `main`
     *   newMain = The main function to call if argument parsing is successful
     *   initialValue = An optional initial state for the `COMMAND` struct
     *
     * Returns:
     *   The return value of `newMain`, or `0` if `newMain` returns `void`.
     */
    static int parseArgs(string[] args, scope int delegate(ref COMMAND, string[]) newMain,
            auto ref COMMAND initialValue = COMMAND.init) {
        alias value = initialValue;
        auto res = parseKnownArgs(value, args);
        if (!res)
            return res.exitCode;
        return newMain(value, args);
    }

    //// Ditto
    static int parseArgs(string[] args, scope void function(ref COMMAND, string[]) newMain,
            auto ref COMMAND initialValue = COMMAND.init) {
        return parseArgs(args, (ref COMMAND cmd, string[] args) { newMain(cmd, args); return 0; }, initialValue);
    }

    /// Ditto
    static int parseArgs(string[] args, scope void delegate(ref COMMAND, string[]) newMain,
            auto ref COMMAND initialValue = COMMAND.init) {
        return parseArgs(args, (ref COMMAND cmd, string[] args) { newMain(cmd, args); return 0; }, initialValue);
    }

    /// Ditto
    static int parseArgs(string[] args, scope int function(ref COMMAND, string[]) newMain,
            auto ref COMMAND initialValue = COMMAND.init) {
        return parseArgs(args, (ref COMMAND cmd, string[] args) => newMain(cmd, args), initialValue);
    }

    /// Ditto
    static int parseArgs(string[] args, scope int delegate(COMMAND, string[]) newMain,
            auto ref COMMAND initialValue = COMMAND.init) {
        return parseArgs(args, (ref COMMAND cmd, string[] args) => newMain(cmd, args), initialValue);
    }

    //// Ditto
    static int parseArgs(string[] args, scope void function(COMMAND, string[]) newMain,
            auto ref COMMAND initialValue = COMMAND.init) {
        return parseArgs(args, (ref COMMAND cmd, string[] args) { newMain(cmd, args); return 0; }, initialValue);
    }

    /// Ditto
    static int parseArgs(string[] args, scope void delegate(COMMAND, string[]) newMain,
            auto ref COMMAND initialValue = COMMAND.init) {
        return parseArgs(args, (ref COMMAND cmd, string[] args) { newMain(cmd, args); return 0; }, initialValue);
    }

    /// Ditto
    static int parseArgs(string[] args, scope int function(COMMAND, string[]) newMain,
            auto ref COMMAND initialValue = COMMAND.init) {
        return parseArgs(args, (ref COMMAND cmd, string[] args) => newMain(cmd, args), initialValue);
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
        return CLI!(config, Complete!COMMAND).parseArgs(args, comp =>
            comp.cmd.match!(_ => _.execute!(config, COMMAND))
        );
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

            static if (is(typeof(newMain(value))))
            {
                // newMain has one parameter so strictly parse command line
                auto res = CLI!(config, COMMAND).parseArgs(value, argv);
            }
            else
            {
                // newMain has two parameters so parse only known arguments
                auto res = CLI!(config, COMMAND).parseKnownArgs(value, argv);
            }

            if (!res)
            return res.exitCode;

            // call newMain
            static if (is(typeof(newMain(value)) == void))
            {
                newMain(value);
                return 0;
            }
            else static if (is(typeof(newMain(value))))
            {
                return newMain(value);
            }
            else static if (is(typeof(newMain(value, [])) == void))
            {
                newMain(value, argv);
                return 0;
            }
            else
            {
                return newMain(value, argv);
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

    assert(CLI!T.parseArgs(["-a", "kiwi"], (T t) { assert(false); }) != 0);    // "kiwi" is not allowed
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

    assert(CLI!T.parseArgs(["-g"], (T t) { assert(false); }) != 0);
    assert(CLI!T.parseArgs([], (T t) { assert(t == T.init); return 12345; }) == 12345);
    assert(CLI!T.parseArgs([], (T t, string[] args) {
        assert(t == T.init);
        assert(args.length == 0);
        return 12345;
    }) == 12345);
    assert(CLI!T.parseArgs(["-a","aa","-g"], (T t, string[] args) {
        assert(t == T("aa"));
        assert(args == ["-g"]);
        return 12345;
    }) == 12345);
    assert(CLI!T.parseArgs(["--color"], (T t) {
        assert(t.color);
        return 12345;
    }) == 12345);
    assert(CLI!T.parseArgs(["--color","never"], (T t) {
        assert(!t.color);
        return 12345;
    }) == 12345);
}

unittest
{
    struct T
    {
        string a;
        string b;
    }

    assert(CLI!T.parseArgs(["-a","A","--"], (T t, string[] args) {
        assert(t == T("A"));
        assert(args == []);
        return 12345;
    }) == 12345);

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
        CLI!T.parseArgs([], (T t, string[] args) {
            assert(t == T.init);
            assert(args.length == 0);
            throw new Exception("My Message.");
        }))
    == "My Message.");
    assert(collectExceptionMsg(
        CLI!T.parseArgs(["-a","aa","-g"], (T t, string[] args) {
            assert(t == T("aa"));
            assert(args == ["-g"]);
            throw new Exception("My Message.");
        }))
    == "My Message.");
    assert(CLI!T.parseArgs([], (T t, string[] args) {
        assert(t == T.init);
        assert(args.length == 0);
    }) == 0);
    assert(CLI!T.parseArgs(["-a","aa","-g"], (T t, string[] args) {
        assert(t == T("aa"));
        assert(args == ["-g"]);
    }) == 0);
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
