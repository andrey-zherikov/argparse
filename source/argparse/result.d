module argparse.result;

import argparse.helpinfo: CommandHelpInfo;


struct Result
{
    ////////////////////////////////////////////////////////////////
    /// Public API
    ////////////////////////////////////////////////////////////////

    int exitCode() const
    {
        return resultCode;
    }

    bool isSuccess   () const { return status == Status.success;    }
    bool isError     () const { return status == Status.error;      }
    bool isHelpWanted() const { return status == Status.helpWanted; }
    
    bool opCast(T : bool)() const
    {
        return isSuccess;
    }


    static enum Success = Result(0, Status.success);

    static auto Error(T...)(int resultCode, string msg, T extraArgs)
    {
        import std.conv: text;

        return Result(resultCode, Status.error, [text(msg, extraArgs)]);
    }

    ////////////////////////////////////////////////////////////////
    /// Private API
    ////////////////////////////////////////////////////////////////

    private this(int i, Status s, string[] err = null) { resultCode = i; status = s; errorMsgs = err; }

    package static enum HelpWanted = Result(0, Status.helpWanted);

    private int resultCode;

    private enum Status { error, success, helpWanted };
    private Status status;

    // A result can carry more than one error message: the checks that run when parsing is over are
    // independent from each other, so all of them are reported rather than just the first one.
    private string[] errorMsgs;

    package const(string)[] errorMessages() const { return errorMsgs; }

    // Merges an error into this result: a success absorbs it, an error accumulates its messages.
    // Only the error state takes part in the merge - `cmdHelpInfo` is left alone.
    package void opOpAssign(string op : "~")(Result other)
    {
        if(!other.isError)
            return;

        if(!isError)
        {
            status = Status.error;
            resultCode = other.resultCode;
        }

        errorMsgs ~= other.errorMsgs;
    }

    // Help information for the stack of commands that was active when this result was produced.
    // It is populated by the parser unless Config.helpOnError is `none`. Successful results
    // carry it as well, so that errors that are detected after parsing has completed (unrecognized
    // arguments) can still print the help screen of the command that was actually being parsed.
    package CommandHelpInfo[] cmdHelpInfo;

    version(unittest)
    {
        package bool isError(string text0, string[] text...)
        {
            import std.algorithm: canFind;
            import std.array: join;

            if(status != Status.error)
                return false;   // success is not an error

            auto allMsgs = errorMsgs.join("\n");

            foreach(s; [text0] ~ text)
                if(!allMsgs.canFind(s))
                    return false;   // can't find required text

            return true;    // all required text is found
        }
    }
}

unittest
{
    assert(Result.Success);
    assert(Result.Success.isSuccess);
    assert(!Result.Success.isError);
    assert(!Result.Success.isError("text"));
    assert(!Result.Success.isHelpWanted);
    assert(Result.Success.errorMessages.length == 0);
    
    assert(!Result.Error(5, ""));
    assert(Result.Error(5, "").exitCode == 5);
    assert(Result.Error(5, "").isError);
    assert(!Result.Error(5, "").isSuccess);
    assert(!Result.Error(5, "").isHelpWanted);

    assert(Result.HelpWanted.isHelpWanted);
    assert(!Result.HelpWanted.isSuccess);
    assert(!Result.HelpWanted.isError);

    auto r = Result.Error(1, "some text",",","more text");
    assert(r.isError("some", "more"));
    assert(!r.isError("other text"));
    assert(r.errorMessages == ["some text,more text"]);
}

unittest
{
    // Merging a success changes nothing
    {
        auto res = Result.Success;
        res ~= Result.Success;
        assert(res.isSuccess);
        assert(res.errorMessages.length == 0);
    }
    {
        auto res = Result.Error(5, "first");
        res ~= Result.Success;
        assert(res.isError("first"));
        assert(res.exitCode == 5);
        assert(res.errorMessages == ["first"]);
    }

    // A success absorbs an error along with its exit code
    {
        auto res = Result.Success;
        res ~= Result.Error(5, "first");
        assert(res.isError("first"));
        assert(res.exitCode == 5);
        assert(res.errorMessages == ["first"]);
    }

    // Errors accumulate; the exit code of the first one wins
    {
        auto res = Result.Success;
        res ~= Result.Error(5, "first");
        res ~= Result.Error(7, "second");
        assert(res.exitCode == 5);
        assert(res.errorMessages == ["first","second"]);

        // every message is searched
        assert(res.isError("first"));
        assert(res.isError("second"));
        assert(res.isError("first","second"));
        assert(!res.isError("third"));
    }

    // Help information is not touched by the merge
    {
        auto res = Result.Success;
        res.cmdHelpInfo = [CommandHelpInfo(name: "prog")];
        res ~= Result.Error(1, "first");
        assert(res.cmdHelpInfo.length == 1 && res.cmdHelpInfo[0].name == "prog");
    }
}
