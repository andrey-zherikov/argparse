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

        return Result(resultCode, Status.error, text(msg, extraArgs));
    }

    ////////////////////////////////////////////////////////////////
    /// Private API
    ////////////////////////////////////////////////////////////////

    private this(int i, Status s, string err = "") { resultCode = i; status = s; errorMsg = err; }

    package static enum HelpWanted = Result(0, Status.helpWanted);

    private int resultCode;

    private enum Status { error, success, helpWanted };
    private Status status;

    private string errorMsg;

    package string errorMessage() const { return errorMsg; }

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

            if(status != Status.error)
                return false;   // success is not an error

            foreach(s; [text0] ~ text)
                if(!errorMsg.canFind(s))
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
}