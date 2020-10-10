/*
Copyright (c) 2018-2020 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003
Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dagon.core.config;

import std.stdio;
import std.process;
import std.string;
import dlib.core.memory;
import dlib.core.ownership;
import dlib.filesystem.filesystem;
import dlib.filesystem.stdfs;
import dagon.core.vfs;
import dagon.core.props;

class Configuration: Owner
{
    protected:
    VirtualFileSystem fs;

    public:
    Properties props;

    this(Owner o)
    {
        super(o);

        fs = New!VirtualFileSystem();
        fs.mount(".");

        string homeDirVar = "";
        version(Windows) homeDirVar = "APPDATA";
        version(Posix) homeDirVar = "HOME";
        auto homeDir = environment.get(homeDirVar, "");
        if (homeDir.length)
        {
            string appdataDir = format("%s/.dagon", homeDir);
            fs.mount(appdataDir);
        }

        props = New!Properties(this);
    }

    ~this()
    {
        Delete(fs);
    }

    bool fromFile(string filename)
    {
        FileStat stat;
        if (fs.stat(filename, stat))
        {
            auto istrm = fs.openForInput(filename);
            auto input = readText(istrm);
            Delete(istrm);
            props.parse(input);
            Delete(input);
            return true;
        }
        else
            return false;
    }
}
