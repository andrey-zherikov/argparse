module argparse.internal.completer;

import argparse.config;
import argparse.result;
import argparse.api.ansi: ansiStylingArgument;
import argparse.api.argument: NamedArgument, PositionalArgument, Description, Optional;
import argparse.api.command: Command, Description, ShortDescription;
import argparse.api.restriction: MutuallyExclusive;
import argparse.api.subcommand: SubCommand, Default;
import argparse.internal.commandinfo: CommandInfo;
import argparse.internal.commandstack;
import argparse.internal.tokenizer: Tokenizer, SubCommandToken = SubCommand;

import std.traits: getUDAs;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private string defaultCommandName(COMMAND)()
{
    static if(getUDAs!(COMMAND, CommandInfo).length > 0 || getUDAs!(COMMAND, Command).length > 0)
    {
        static if(getUDAs!(COMMAND, CommandInfo).length > 0)
            enum names = getUDAs!(COMMAND, CommandInfo)[0].names;
        else
            enum names = CommandInfo.init.names;

        static if(names.length > 0 && names[0] != "")
            return names[0];
        else
        {
            import core.runtime: Runtime;
            import std.path: baseName;
            return Runtime.args[0].baseName;
        }
    }
    else
        return COMMAND.stringof;
}

unittest
{
    import core.runtime: Runtime;
    import std.path: baseName;

    @Command
    struct T {}

    assert(defaultCommandName!T == Runtime.args[0].baseName);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@(Command("complete")
.Description("Print completion.")
)
private struct CompleteCmd
{
    @MutuallyExclusive
    {
        @(NamedArgument.Description("Provide completion for bash."))
        bool bash;
        @(NamedArgument.Description("Provide completion for tcsh."))
        bool tcsh;
        @(NamedArgument.Description("Provide completion for fish."))
        bool fish;
    }

    @(PositionalArgument(0).Optional)
    string[] args;

    void execute(Config config, COMMAND)()
    {
        import std.process: environment;
        import std.stdio: writeln;
        import std.algorithm: each;

        if(bash)
        {
            // According to bash documentation:
            //   When the function or command is invoked, the first argument ($1) is the name of the command whose
            //   arguments are being completed, the second` argument ($2) is the word being completed, and the third
            //   argument ($3) is the word preceding the word being completed on the current command line.
            //
            // We don't use these arguments so we just remove those after "---" including itself
            while(args.length > 0 && args[$-1] != "---")
                args = args[0..$-1];

            // Remove "---"
            if(args.length > 0 && args[$-1] == "---")
                args = args[0..$-1];

            // COMP_LINE environment variable contains current command line so if it ends with space ' ' then we
            // should provide all available arguments. To do so, we add an empty argument
            auto cmdLine = environment.get("COMP_LINE", "");
            if(cmdLine.length > 0 && cmdLine[$-1] == ' ')
                args ~= "";
        }
        else if(tcsh || fish)
        {
            // COMMAND_LINE environment variable contains current command line so if it ends with space ' ' then we
            // should provide all available arguments. To do so, we add an empty argument
            auto cmdLine = environment.get("COMMAND_LINE", "");
            if(cmdLine.length > 0 && cmdLine[$-1] == ' ')
                args ~= "";
        }

        completeArgs!(config, COMMAND)(args).each!writeln;
    }
}

package(argparse) struct Complete(COMMAND)
{
    @(Command("init")
    .Description("Print initialization script for shell completion.")
    .ShortDescription("Print initialization script.")
    )
    private struct InitCmd
    {
        @MutuallyExclusive
        {
            @(NamedArgument.Description("Provide completion for bash."))
            bool bash;
            @(NamedArgument.Description("Provide completion for zsh."))
            bool zsh;
            @(NamedArgument.Description("Provide completion for tcsh."))
            bool tcsh;
            @(NamedArgument.Description("Provide completion for fish."))
            bool fish;
        }

        @(NamedArgument.Description("Path to completer. Default value: path to this executable."))
        string completerPath; // path to this binary

        @(NamedArgument.Description("Command name. Default value: "~defaultCommandName!COMMAND~"."))
        string commandName;   // command to complete

        void execute(Config config, COMMAND)()
        {
            import std.stdio: writeln;

            if(completerPath.length == 0)
            {
                import std.file: thisExePath;
                completerPath = thisExePath();
            }

            string commandNameArg;
            if(commandName == "")
                commandName = defaultCommandName!COMMAND;
            else if(commandName != defaultCommandName!COMMAND)
                commandNameArg = " --commandName "~commandName;

            if(bash)
            {
                // According to bash documentation:
                //   When the function or command is invoked, the first argument ($1) is the name of the command whose
                //   arguments are being completed, the second` argument ($2) is the word being completed, and the third
                //   argument ($3) is the word preceding the word being completed on the current command line.
                //
                // So we add "---" argument to distinguish between the end of actual parameters and those that were added by bash

                writeln("# Add this source command into .bashrc:");
                writeln("#       source <(", completerPath, " init --bash", commandNameArg, ")");
                // 'eval' is used to properly get arguments with spaces. For example, in case of "1 2" argument,
                // we will get "1 2" as is, compare to "\"1", "2\"" without 'eval'.
                writeln("complete -C 'eval ", completerPath, " --bash -- $COMP_LINE ---' ", commandName);
            }
            else if(zsh)
            {
                // We use bash completion for zsh
                writeln("# Ensure that you called compinit and bashcompinit like below in your .zshrc:");
                writeln("#       autoload -Uz compinit && compinit");
                writeln("#       autoload -Uz bashcompinit && bashcompinit");
                writeln("# And then add this source command after them into your .zshrc:");
                writeln("#       source <(", completerPath, " init --zsh", commandNameArg, ")");
                writeln("complete -C 'eval ", completerPath, " --bash -- $COMP_LINE ---' ", commandName);
            }
            else if(tcsh)
                {
                    // Comments start with ":" in tsch
                    writeln(": Add this eval command into .tcshrc:   ;");
                    writeln(":       eval `", completerPath, " init --tcsh", commandNameArg, "`     ;");
                    writeln("complete ", commandName, " 'p,*,`", completerPath, " --tcsh -- $COMMAND_LINE`,'");
                }
                else if(fish)
                    {
                        writeln("# Add this source command into ~/.config/fish/config.fish:");
                        writeln("#       ", completerPath, " init --fish", commandNameArg, " | source");
                        writeln("complete -c ", commandName, " -a '(COMMAND_LINE=(commandline -p) ", completerPath, " --fish -- (commandline -op))' --no-files");
                    }
        }
    }

    SubCommand!(InitCmd, Default!CompleteCmd) cmd;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private string[] completeArgs(Config config, CommandStack cmdStack, string[] args)
{
    ansiStylingArgument.isEnabled = config.detectAnsiSupport();

    // Ignore last argument while processing command line
    foreach(entry; Tokenizer(config, args[0..$-1], &cmdStack))
    {
        import std.sumtype: match;

        // Process subcommands only and ignore everything else
        entry.match!(
                (ref SubCommandToken c) { cmdStack.addCommand(c.cmdInit()); },
                (ref _) {}
            );
    }

    // Provide suggestions for the last argument only
    return cmdStack.getSuggestions(args[$-1]);
}

package(argparse) string[] completeArgs(Config config, COMMAND)(string[] args)
{
    COMMAND dummy;

    return completeArgs(config, createCommandStack!config(dummy), args.length == 0 ? [""] : args);
}

