import std.stdio;
import std.path;
import std.file;
import std.array;
import std.process;
import std.parallelism;

immutable string root_path = __FILE_FULL_PATH__.dirName.chainPath("..").asNormalizedPath.array;
immutable string source_path = root_path.chainPath("source").array;
immutable string code_snippets_path = root_path.chainPath("docs", "code_snippets").array;

int main()
{
    writeln("Root directory: ", root_path);
    writeln("Source directory: ", source_path);
    writeln("Code snippets directory: ", code_snippets_path);

    shared bool failed = false;

    foreach(file; parallel(dirEntries(code_snippets_path, "*.d",SpanMode.shallow), 1))
    {
        if(!failed)
        {
            writeln("\nBuilding ", file);

            immutable command = [
                "rdmd",
                `--eval=mixin(import("` ~ file.baseName ~ `"))`,
                `-I` ~ source_path,
                `-J` ~ code_snippets_path
            ];

            auto proc = execute(command);
            if(proc.status != 0)
            {
                writeln("Command `", command, "` failed, output:");
                writeln(proc.output);
                failed = true;
            }
        }
    }

    return failed ? 1 : 0;
}