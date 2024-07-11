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

    static int parseArgs(alias newMain)(string[] args, COMMAND initialValue = COMMAND.init)
    if(__traits(compiles, { newMain(COMMAND.init); }))
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

    static int parseArgs(alias newMain)(string[] args, COMMAND initialValue = COMMAND.init)
    if(__traits(compiles, { newMain(COMMAND.init, string[].init); }))
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
    struct Args {}

    mixin CLI!({
        Config cfg;
        cfg.errorHandler = (string s) {};
        return cfg;
    }(), Args).main!((_){});
}
