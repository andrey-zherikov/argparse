import argparse.ansi;

void printText(bool enableStyle)
{
    // style is enabled at runtime when `enableStyle` is true
    auto myStyle = enableStyle ? bold.italic.cyan.onRed : noStyle;

    // "Hello" is always printed in green;
    // "world!" is printed in bold, italic, cyan and on red when `enableStyle` is true, or "as is" otherwise
    writeln(green("Hello "), myStyle("world!"));
}

printText(true);
printText(false);