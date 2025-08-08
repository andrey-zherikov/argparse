module argparse.internal.commandstack;

import argparse.config;
import argparse.result;
import argparse.internal.command;
import argparse.internal.commandinfo: getTopLevelCommandInfo;

import std.range: back, popBack;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct FindResult
{
    Command.Argument arg;

    Command[] cmdStack;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct CommandStack
{
    Command[] stack;

    size_t idxCurPositionalCmd;

    private this(Command cmd)
    {
        stack = [cmd];
    }

    void addCommand(Command cmd)
    {
        stack ~= cmd;
    }

    string[] getSuggestions(string arg) const
    {
        import std.algorithm: map, sort, uniq;
        import std.array: array;
        import std.range: join;

        return stack.map!((ref _) => _.suggestions(arg)).join.sort.uniq.array;
    }

    auto finalize(const Config config)
    {
        foreach(ref cmd; stack)
        {
            auto res = cmd.finalize(config, this);
            if(!res)
                return res;
        }

        return Result.Success;
    }

    auto findSubCommand(string name)
    {
        // Look up in comand stack
        foreach_reverse(ref cmd; stack)
        {
            auto res = cmd.getSubCommand(name);
            if(res)
                return res;
        }
        // Look up through default subcommands
        for(auto newStack = stack[]; newStack.back.defaultSubCommand !is null;)
        {
            newStack ~= newStack.back.defaultSubCommand();

            auto res = newStack.back.getSubCommand(name);
            if(res)
            {
                // update stack
                stack = newStack;

                return res;
            }
        }
        return null;
    }


    FindResult getNextPositionalArgument(bool lookInDefaultSubCommands)
    {
        // Look up in current command stack
        while(true)
        {
            auto res = stack[idxCurPositionalCmd].getNextPositionalArgument();
            if(res)
                return FindResult(res, stack[0..idxCurPositionalCmd+1]);

            if(idxCurPositionalCmd == stack.length-1)
                break;

            ++idxCurPositionalCmd;
        }

        if(lookInDefaultSubCommands)
        {
            for(auto newStack = stack[]; newStack.back.defaultSubCommand !is null;)
            {
                newStack ~= newStack.back.defaultSubCommand();

                auto res = newStack.back.getNextPositionalArgument();
                if(res)
                {
                    // update stack
                    stack = newStack;
                    idxCurPositionalCmd = stack.length-1;

                    return FindResult(res, newStack);
                }
            }
        }
        return FindResult.init;
    }


    private FindResult findNamedArgument(Command.Argument delegate(ref Command) find)
    {
        // Look up in command stack
        for(auto newStack = stack[]; newStack.length > 0; newStack.popBack)
        {
            auto res = find(newStack.back);
            if(res)
            return FindResult(res, newStack);
        }

        // Look up through default subcommands
        for(auto newStack = stack[]; newStack.back.defaultSubCommand !is null;)
        {
            newStack ~= newStack.back.defaultSubCommand();

            auto res = find(newStack.back);
            if(res)
            {
                // update stack
                stack = newStack;

                return FindResult(res, newStack);
            }
        }

        return FindResult.init;
    }

    FindResult findShortArgument(string name)
    {
        return findNamedArgument((ref cmd) => cmd.findShortNamedArgument(name));
    }

    FindResult findLongArgument(string name)
    {
        return findNamedArgument((ref cmd) => cmd.findLongNamedArgument(name));
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package auto createCommandStack(Config config, COMMAND)(ref COMMAND receiver)
{
    return CommandStack(createCommand!config(receiver, getTopLevelCommandInfo!COMMAND(config)));
}
