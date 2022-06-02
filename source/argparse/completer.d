module argparse.completer;

import argparse;

import std.traits: getUDAs;
import std.sumtype: SumType;



private template defaultCommandName(COMMAND)
{
    static if(getUDAs!(COMMAND, CommandInfo).length > 0)
        enum defaultCommandName = getUDAs!(COMMAND, CommandInfo)[0].names[0];
    else
        enum defaultCommandName = COMMAND.stringof;
}


package struct Complete(COMMAND)
{
    @(Command("init")
    .Description("Print initialization script for shell completion.")
    .ShortDescription("Print initialization script.")
    )
    struct Init
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
        string commandName = defaultCommandName!COMMAND;   // command to complete

        void execute(Config config)()
        {
            import std.stdio: writeln;

            if(completerPath.length == 0)
            {
                import std.file: thisExePath;
                completerPath = thisExePath();
            }

            string commandNameArg;
            if(commandName != defaultCommandName!COMMAND)
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

    @(Command("complete")
    .Description("Print completion.")
    )
    struct Complete
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

        @TrailingArguments
        string[] args;

        void execute(Config config)()
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

            CLI!(config, COMMAND).completeArgs(args).each!writeln;
        }
    }

    @SubCommands
    SumType!(Init, Default!Complete) cmd;
}