### Installing

**Windows** - unzip it and run `hexmaw.exe`. Everything it needs is in the folder. It isn't code-signed, so Windows may say it "protected your PC": click "More info", then "Run anyway".

**Linux** - unpack it and run `./hexmaw`. Everything it needs is in the folder; sound goes through PulseAudio or PipeWire.

**macOS (Apple silicon)** - unpack it. The build isn't signed or notarized, so Gatekeeper refuses it until you clear its quarantine once, in a terminal in its folder: `xattr -dr com.apple.quarantine Hexmaw.app`. Then open Hexmaw.app. It is built and checked automatically on macOS, but nobody has played it through on a Mac yet.

Every build needs OpenGL 3.3. `hexmaw check` checks an installation and names anything missing; saves and the log go to `%LOCALAPPDATA%\hexmaw\` on Windows and `~/.local/share/hexmaw/` elsewhere. README.txt in the archive says more, with the controls.
