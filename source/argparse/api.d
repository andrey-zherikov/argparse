module argparse.api;

import argparse.config;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Public API
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

struct Param(VALUE_TYPE)
{
    const Config* config;
    string name;

    static if(!is(VALUE_TYPE == void))
        VALUE_TYPE value;
}

alias RawParam = Param!(string[]);

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Default subcommand
struct Default(COMMAND)
{
    COMMAND command;
    alias command this;
}

package enum isDefault(T) = is(T == Default!ORIG_TYPE, ORIG_TYPE);

package alias RemoveDefault(T : Default!ORIG_TYPE, ORIG_TYPE) = ORIG_TYPE;
package alias RemoveDefault(T) = T;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

struct TrailingArguments {}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////