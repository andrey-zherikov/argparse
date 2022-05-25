// This example shows the usage of a separate main for completer

import argparse;
import cli;

// This mixin defines standard main function that parses command line and prints completion result to stdout
mixin CLI!Program.mainComplete;