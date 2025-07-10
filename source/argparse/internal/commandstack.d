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

    size_t[] idxPositionalStack;
    size_t idxNextPositional = 0;

    private this(Command cmd)
    {
        stack = [cmd];
        idxPositionalStack = [0];
    }

    void addCommand(Command cmd)
    {
        stack ~= cmd;
        idxPositionalStack ~= idxNextPositional;
    }

    const(string)[] getSuggestions(string arg)
    {
        import std.range: join;
        import std.algorithm : map;

        return stack.map!((ref _) => _.suggestions(arg)).join;
    }

    auto checkRestrictions()
    {
        foreach(ref cmd; stack)
        {
            auto res = cmd.checkRestrictions();
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
        // Actual stack can be longer than the one we looked up through last time
        // because parsing of named argument can add default commands into it
        for(auto stackSize = idxPositionalStack.length; stackSize <= stack.length; ++stackSize)
        {
            if(idxPositionalStack.length < stackSize)
                idxPositionalStack ~= idxNextPositional;

            auto newStack = stack[0..stackSize];

            auto res = newStack.back.findPositionalArgument(idxNextPositional - idxPositionalStack[$-1]);
            if(res)
            {
                idxNextPositional++;
                return FindResult(res, newStack);
            }
        }

        if(lookInDefaultSubCommands)
        {
            for(auto newStack = stack[], posStack = idxPositionalStack; newStack.back.defaultSubCommand !is null;)
            {
                newStack ~= newStack.back.defaultSubCommand();
                posStack ~= idxNextPositional;

                auto res = newStack.back.findPositionalArgument(0);  // position is always 0 in new sub command
                if(res)
                {
                    // update stack
                    stack = newStack;
                    idxPositionalStack = posStack;

                    idxNextPositional++;
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
