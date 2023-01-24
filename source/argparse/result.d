module argparse.result;


struct Result
{
    int  resultCode;

    package enum Status { failure, success, unknownArgument };
    package Status status;

    package string errorMsg;

    package const(string)[] suggestions;

    package static enum Failure = Result(1, Status.failure);
    package static enum Success = Result(0, Status.success);
    package static enum UnknownArgument = Result(0, Status.unknownArgument);

    bool opCast(T : bool)() const
    {
        return status == Status.success;
    }

    package static auto Error(A...)(A args)
    {
        import std.conv: text;

        return Result(1, Status.failure, text!A(args));
    }

    version(unittest)
    {
        package bool isError(string text)
        {
            import std.algorithm: canFind;
            return (!cast(bool) this) && errorMsg.canFind(text);
        }
    }
}