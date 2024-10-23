module argparse.api.cli;

import argparse.config;
import argparse.result;

import argparse.internal.parser: callParser;
import argparse.internal.completer: completeArgs, Complete;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Public API for CLI wrapper
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

template CLI(Config config, COMMANDS...)
{
    mixin template main(alias newMain)
    {
        import std.sumtype: SumType, match;

        private struct Program
        {
            SumType!COMMANDS cmd;   // Sub-commands
        }

        private auto forwardMain(Args...)(Program prog, auto ref Args args)
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
        return callParser!(config, false)(receiver, args, unrecognizedArgs);
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
            config.onError(res.errorMsg);
        }

        return res;
    }

    static int parseArgs(alias newMain)(string[] args, auto ref COMMAND initialValue = COMMAND.init)
    if(__traits(compiles, { newMain(initialValue); }))
    {
        alias value = initialValue;

        auto res = parseArgs(value, args);
        if(!res)
            return res.resultCode;

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
            return res.resultCode;

        static if(__traits(compiles, { int a = cast(int) newMain(value, args); }))
            return cast(int) newMain(value, args);
        else
        {
            newMain(value, args);
            return 0;
        }
    }

    string[] completeArgs(string[] args)
    {
        return .completeArgs!(config, COMMAND)(args);
    }

    int complete(string[] args)
    {
        import std.sumtype: match;

        // dmd fails with core.exception.OutOfMemoryError@core\lifetime.d(137): Memory allocation failed
        // if we call anything from CLI!(config, Complete!COMMAND) so we have to directly call parser here

        Complete!COMMAND receiver;
        string[] unrecognizedArgs;

        auto res = callParser!(config, false)(receiver, args, unrecognizedArgs);
        if(!res)
            return 1;

        if(res && unrecognizedArgs.length > 0)
        {
            import std.conv: to;
            config.onError("Unrecognized arguments: "~unrecognizedArgs.to!string);
            return 1;
        }

        receiver.cmd.match!(_ => _.execute!config());

        return 0;
    }

    mixin template mainComplete()
    {
        int main(string[] argv)
        {
            return CLI!(config, COMMAND).complete(argv[1..$]);
        }
    }

    mixin template main(alias newMain)
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

    enum cfg = Config.init;

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

    enum cfg = Config.init;

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
