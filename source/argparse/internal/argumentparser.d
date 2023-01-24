module argparse.internal.argumentparser;

import argparse : NamedArgument;
import argparse.config;
import argparse.result;
import argparse.param;
import argparse.internal.argumentuda: getMemberArgumentUDA;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private alias ParseFunction(COMMAND_STACK, RECEIVER) = Result delegate(const COMMAND_STACK cmdStack, Config* config, ref RECEIVER receiver, string argName, string[] rawValues);

private alias ParsingArgument(COMMAND_STACK, RECEIVER, alias symbol, alias uda, bool completionMode) =
    delegate(const COMMAND_STACK cmdStack, Config* config, ref RECEIVER receiver, string argName, string[] rawValues)
    {
        static if(completionMode)
        {
            return Result.Success;
        }
        else
        {
            try
            {
                auto res = uda.info.checkValuesCount(argName, rawValues.length);
                if(!res)
                    return res;

                auto param = RawParam(config, argName, rawValues);

                auto target = &__traits(getMember, receiver, symbol);

                static if(is(typeof(target) == function) || is(typeof(target) == delegate))
                    return uda.parsingFunc.parse(target, param);
                else
                    return uda.parsingFunc.parse(*target, param);
            }
            catch(Exception e)
            {
                return Result.Error(argName, ": ", e.msg);
            }
        }
    };

package auto getArgumentParsingFunctions(Config config, COMMAND_STACK, TYPE, symbols...)()
{
    ParseFunction!(COMMAND_STACK, TYPE)[] res;

    static foreach(symbol; symbols)
        res ~= ParsingArgument!(COMMAND_STACK, TYPE, symbol, getMemberArgumentUDA!(config, TYPE, symbol, NamedArgument), false);

    return res;
}

package auto getArgumentCompletionFunctions(Config config, COMMAND_STACK, TYPE, symbols...)()
{
    ParseFunction!(COMMAND_STACK, TYPE)[] res;

    static foreach(symbol; symbols)
        res ~= ParsingArgument!(COMMAND_STACK, TYPE, symbol, getMemberArgumentUDA!(config, TYPE, symbol, NamedArgument), true);

    return res;
}
