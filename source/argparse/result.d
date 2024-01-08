module argparse.result;


struct Result
{
    ////////////////////////////////////////////////////////////////
    /// Public API
    ////////////////////////////////////////////////////////////////

    int exitCode() const
    {
        return resultCode;
    }

    bool opCast(T : bool)() const
    {
        return status == Status.success;
    }


    static enum Success = Result(0, Status.success);

    static auto Error(T...)(string msg, T extraArgs)
    {
        return Error(1, msg, extraArgs);
    }
    static auto Error(T...)(int resultCode, string msg, T extraArgs)
    {
        import std.conv: text;

        return Result(resultCode, Status.error, text(msg, extraArgs));
    }

    ////////////////////////////////////////////////////////////////
    /// Private API
    ////////////////////////////////////////////////////////////////

    private this(int i, Status s, string err = "") { resultCode = i; status = s; errorMsg = err; }

    package int resultCode;

    package enum Status { error, success, unknownArgument };
    package Status status;

    package string errorMsg;

    package const(string)[] suggestions;

    package static enum UnknownArgument = Result(0, Status.unknownArgument);

    version(unittest)
    {
        package bool isError(string[] text...)
        {
            import std.algorithm: canFind;

            if(status != Status.error)
                return false;   // success is not an error

            foreach(s; text)
                if(!errorMsg.canFind(s))
                    return false;   // can't find required text

            return true;    // all required text is found
        }
    }
}

unittest
{
    assert(Result.Success);

    assert(!Result.Success.isError);
    assert(!Result.Error(""));
    assert(!Result.Error(5, ""));
    assert(Result.Error("").exitCode == 1);
    assert(Result.Error(5, "").exitCode == 5);

    auto r = Result.Error("some text",",","more text");
    assert(r.isError("some", "more"));
    assert(!r.isError("other text"));
}