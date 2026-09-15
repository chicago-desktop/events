# Where the pictures come from

Copied byte for byte from the Chicago shell's icon set (chicago-desktop/shell,
`assets/icons/{32,16}/text_document.png`), whose `assets/icons/SOURCE.md`
lists it as:

> - File: text_document; Source: w95_60; What it shows: a text document

That is Microsoft's artwork from `shell32.dll` (the Windows 95 `w95_60.ico` of
<https://github.com/trapd00r/win95-winxp_icons>), extracted there from the
original `.ico` file as RGBA PNG at 32 and 16 px. It is not part of the
module under MIT, and it is an interim icon set that is being replaced with
original pixel art (chicago-desktop/shell#1). The file name is the picture's
name in the pack, `chicago.events:images/text_document`.
