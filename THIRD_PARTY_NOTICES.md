# Third-party notices

## yoursAnthony/XiaomiPCManager-Locale-Patch

The native-layer patching technique in `scripts/` (PRI resource patching via
`makepri`, the `SetThreadUILanguage` assembly injection via Mono.Cecil, the
UTF-16 native string replacement, the clipboard resource patcher, and the
keyboard-backlight OSD image redraw) is adapted from
[yoursAnthony/XiaomiPCManager-Locale-Patch](https://github.com/yoursAnthony/XiaomiPCManager-Locale-Patch),
Copyright (c) yoursAnthony, licensed under the MIT License.

The `translations/pri-en.json` and `translations/clipboard-en.json`
dictionaries originate from that project as well.

Adaptations in this repository: version pinning was replaced with capability
detection and graceful degradation (unknown builds are patched best-effort,
unmatched strings stay Chinese with a warning), the update-dialog replacement
is pattern-based across all update-display closures instead of a fixed
compiler-generated closure name, and partial dictionary matches are allowed.

The full MIT license text of the source project:

> MIT License
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

## Mono.Cecil

Downloaded on demand from NuGet (pinned version 0.11.6) by the installer and
used to rewrite the app's .NET assemblies. Copyright (c) Jb Evain,
MIT licensed: https://github.com/dotnet/cecil

## Microsoft.Windows.SDK.BuildTools

Downloaded on demand from NuGet (pinned version 10.0.26100.1742); provides
`makepri.exe` used to dump and rebuild the app's PRI resource files.
Copyright (c) Microsoft Corporation.
https://www.nuget.org/packages/Microsoft.Windows.SDK.BuildTools

## Xiaomi PC Manager

Xiaomi PC Manager (小米电脑管家) is proprietary software of Xiaomi Inc. This
project distributes no Xiaomi code: all patching happens locally against the
user's own installation.
