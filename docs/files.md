# Files

Spore's file manager: the basics you'd miss coming from macOS or Windows,
ready from the first login, with the same theme as the rest. For anything
it doesn't do, a mature file manager (Thunar, Nautilus, Dolphin) installs
next to it.

## Opening it

- **Files** in the app launcher (`rofi -show drun`).
- `spore-files [folder]` in a terminal or a niri shortcut:
  `Mod+Alt+F { spawn "spore-files"; }`. With a file instead of a folder it
  opens its folder with the file selected; with nothing, home;
  `spore-files recent:///`, Recent.

Each call opens a window. They're regular windows: niri tiles them, moves
them and closes them like any app's.

To make it the app that opens folders (a drive's, a "show folder" in an
app, `xdg-open ~/Downloads`), instead of another file manager:

```bash
gio mime inode/directory spore-files.desktop
```

A browser's "Show in folder" goes another way, the `FileManager1` D-Bus
service, which Files doesn't provide: that still opens Thunar or whichever
file manager provides it.

## What it does

- **The places on the left:** Recent (below), Home and your folders
  (Desktop, Documents, Downloads, Music, Pictures, Videos), the ones that
  exist, with the names they have on your system, and the Trash. Then your **Favorites**: any
  folder, added with the right button (Add to sidebar, on the folder, or on
  the empty part for the open one) and taken away the same way (Remove from
  sidebar). They're GTK's bookmarks, so they're the same ones Thunar and the
  open and save dialogs of GTK apps show. Below them, **Devices**: the
  machine's own disks (File System, which is `/`, and volumes like a Windows
  partition, by their label or the folder they mount on), then the USB
  drives, mounted or not (a click mounts and opens it), each with its eject
  button (Files leaves the drive first if you're in it). A disk that
  `/etc/fstab` mounts opens in its folder there (an automount mounts it
  then); boot, swap and Windows' reserved and recovery partitions aren't
  shown.
- **Recent:** the files you used lately, newest first (up to 100, only the
  ones still there): the ones opened from Files, and the ones other apps
  list in the freedesktop history (`~/.local/share/recently-used.xbel`):
  GTK apps, LibreOffice, the browsers' downloads, Thunar. Two with the same
  name show their folder after it, `notes.txt (~/Work)`. They open, preview,
  copy, cut, drag out and go to the Trash as anywhere else; **Show in its
  folder** (right button) takes you to it, selected. Nothing can be pasted,
  made or dropped there: it isn't a folder. A file opened in Files goes to
  that history too, as Thunar and GTK apps do, so the open dialogs of GTK
  apps list it as well.
- **The path on top:** each piece takes you there. Click the empty part (or
  Ctrl+L) to type a path: `~` is home, `recent:///` Recent, and a
  relative one starts from the open folder.
- **Grid or list:** the list has columns for name, size, kind and date;
  clicking one sorts by it, and clicking it again reverses the order
  (everywhere but Recent, which goes by when).
  Folders always come first, and numbers sort as numbers (img2 before
  img10).
- **Filter:** type anywhere and the folder shows only what contains that
  text (Esc clears it).
- **Thumbnails:** images show themselves (HEIC and WebP too); videos, PDFs
  and the rest show the thumbnail other apps (Thunar, GTK) already left in
  `~/.cache/thumbnails`.
- **Quick view:** Space shows the selected file big, in a panel above
  everything (see below).
- **Opening a file:** double click or Enter opens it with the app your
  system has for that kind of file (the same one other file managers use).
- **It follows the folder:** a file that appears or disappears shows up by
  itself, and the selection stays on the same file.
- **Selecting several:** Ctrl+click adds or takes away, Shift+click (or
  Shift+arrows) selects everything in between, Ctrl+A selects it all.
- **Copy, cut and paste** between folders and windows, **rename** in place
  (F2), **new folder**, and **the Trash** (Delete): see [Copying and moving,
  safely](#copying-and-moving-safely).
  What you copy also goes to the system's clipboard, for other apps: one
  image as the picture itself (paste it in a chat or a document), anything
  else as the list of files (file managers, Chromium-based apps).
- **Drag and drop:** drag files onto a folder, a place on the left (the
  Trash, a USB drive) or a piece of the path on top. Within the same disk
  they move, to another disk they're copied, like in Finder and Explorer (a
  network share, a Flatpak app's files or `/tmp` count as another disk);
  hold Ctrl to copy, Shift to move. Next to the pointer it says what letting
  go there does (`Move “photo.jpg” to “Pictures”`); Esc cancels it, and a
  name that's taken asks like a paste. Dragged out of the window, the files
  go to another app as a copy: drop them on Firefox (a chat, a form) to
  attach them, or on Thunar. Brought back over Files, they drop as usual
  (without the label next to the pointer). Files dragged from another app
  (Thunar, a browser's downloads) drop on a folder, a place on the left or
  the open folder itself (its edge lights up): moved within the same disk,
  copied to another (Ctrl and Shift can't be seen from another app).
- **Compress and extract:** the right button's **Compress** puts what's
  selected in a zip next to it (named after it, or Archive.zip for several;
  not offered for a single file that's already compressed, which gains
  nothing zipped again);
  **Extract here** opens a zip, 7z, rar or tar (.tar.gz, .tar.xz…) into the
  same folder. One folder inside comes out as it is, several things go in a
  folder named after the archive, so you never get `photos/photos`. A name
  that's taken gets a number, the status line shows how far it is (Cancel
  stops it), and one that fails or is canceled leaves nothing behind.
- **The right button** opens a menu with all of that, plus **Open with…**
  (the apps your system has for that kind of file, and optionally make one
  the default), **Copy path** and **Open terminal here** ($TERMINAL, or
  kitty, foot, Alacritty…). On the empty part: New folder, Paste, a terminal
  there. The Menu key or Shift+F10 opens it too.
- **Hidden files:** shown or not with Ctrl+H or the eye button.

The view, the order and the hidden files are remembered
(`~/.local/state/spore/files.json`), the same for every window.

## Keyboard

| Keys | Does |
|---|---|
| Arrows | Move the selection (with Shift: select along) |
| Space | The quick view (again, or Esc: close it) |
| Page Down, Page Up; Ctrl+arrows | In the quick view of a PDF: the next page (Ctrl+Down or Ctrl+Right), the one before (Ctrl+Up or Ctrl+Left) |
| Enter | Open (a folder: go in) |
| Backspace, Alt+Up | Go up a folder |
| Alt+Left, Alt+Right | Back, forward (the mouse's side buttons too) |
| Tab, F6 | To the places on the left: the arrows go through them, a letter jumps to the next one starting with it, Enter opens it, Esc or Tab come back |
| Typing | Filter by name |
| Esc | Close the quick view; clear the filter; clear the selection |
| Home, End | First, last |
| Ctrl+A | Select everything |
| Ctrl+C, Ctrl+X, Ctrl+V | Copy, cut, paste |
| F2 | Rename in place (Enter: done; Esc: leave it) |
| Delete | Move to the Trash (in the Trash: delete for good, it asks) |
| Ctrl+Shift+C | Copy the path (of what's selected, or of the folder) |
| Ctrl+Shift+N | New folder (it's named right away) |
| Menu, Shift+F10 | The menu of what's selected |
| Ctrl+L | Type a path (~ is home, trash:/// the Trash) |
| Ctrl+Shift+T | Go to the Trash |
| Ctrl+F | Go to the filter |
| Ctrl+H | Show or hide the hidden files |
| Ctrl+1, Ctrl+2 | Grid, list |
| Ctrl+N | Another window on the same folder |
| Ctrl+W | Close the window |

## Copying and moving, safely

Nothing is ever overwritten or lost:

- **A name that's already there:** before starting, Files asks. Keep
  both (the new one gets a number: `photo (2).jpg`), Replace (the old one
  goes to the Trash first, so it can be brought back), Skip, or Cancel.
  Pasting into the same folder a copy keeps both, and a move does nothing.
  Replace is refused when what's pasted is inside the old one (the folder
  `photos/photos` pasted next to `photos`): it would go to the Trash too.
- **A copy never leaves half a file:** it's written under a hidden
  temporary name and gets its real name only when it's complete. Cancel
  (in the status line, which shows how far it is) removes the one in
  progress; what was already done stays.
- **Deleting is the Trash.** Deleting for good only happens inside the
  Trash, and it asks first. Folders that can't be written (a Go module
  cache, files from a read-only disk) get write permission back first, so
  the Trash can always be emptied.
- **Folders into themselves:** moving or copying a folder into itself (or
  into one of its folders) is refused.
- A cut is pasted once: then the clipboard is empty. A copy can be pasted
  again, in any Files window.
- If you close the window while a copy runs, the copy finishes first.
- Tens of thousands of items at once can be more than the system passes to
  a program (about 2 MB of paths): then nothing is done, the status line
  says so, and Files goes on working.

## The Trash

The Trash place shows what you deleted, with where each thing came from and
when (in the status line). **Restore** puts it back where it was (the folder
is made again if it's gone; if the name is taken there, it gets a number),
**Delete for good** (Delete, or the menu) and **Empty Trash** ask first.
Inside the Trash nothing can be renamed, cut or pasted into.

It's the home Trash (`~/.local/share/Trash`, the freedesktop one Thunar
and GNOME use too). Things deleted on a USB drive go to that drive's own
Trash, which isn't shown here.

## Quick view

Space shows the selected file big, in a panel above everything, like
macOS's Quick Look. The keyboard stays in the Files window: the arrows keep
moving the selection and the panel follows it, Enter opens the file with
its app, and Space or Esc close it. It also closes when you go to another
window. Moving through files it changes straight from one to the next: it
keeps the last one until the next one is ready, and every text gets the
same page, so going through a folder of code only the text changes.

- **Images:** at their size, or scaled down to fit: PNG, JPEG, WebP, HEIC
  and HEIF (iPhone photos), AVIF, JPEG XL, TIFF, GIF, BMP, SVG (GIFs and
  animated WebPs move).
- **Text:** plain text and code as they are, on a page the same size for
  all of them; Markdown formatted, with nothing fetched from the network
  (its images show as links, and any HTML in it as text).
- **PDFs:** a page at a time, drawn for your screen (the text is sharp):
  the arrows on top, the mouse wheel, Page Up and Page Down, or Ctrl and
  the arrows (for keyboards without the page keys) turn the pages. One
  that's locked or damaged shows its card.
- **Archives:** what a zip, 7z, rar or tar holds, without extracting it:
  a tree, folders first, with what each weighs, and how many files and
  folders there are. A .tar.gz or .tar.xz has to be read whole to list it,
  so a big one takes a moment.
- **Fonts:** TTF, OTF and collections (WOFF too, if Qt can read it), in
  themselves: the name, a sentence in four sizes and every letter and digit.
- **Documents and books:** an ODF document's thumbnail of its first page
  (LibreOffice saves one: Writer, Calc, Impress, Draw) and an EPUB's cover,
  taken out of the file without opening it. One without them shows its
  card. Office files (Word, Excel…) show their card.
- **Videos and songs:** they play, with a bar to pause and seek. The
  player is a process of its own that ends when the view moves on or closes,
  so Files doesn't keep the video's memory (more than 300 MB for a 4K
  video).
- **Anything else:** a card with its kind, size, date and folder (and its
  thumbnail, if other apps left one).

## How it runs

Files is another Quickshell process, not the shell's: it exists only while
it has a window open (the last one to close takes it and its memory away),
and if it ever hangs, the bar and the lockscreen don't go with it. It follows
the shell's theme live through `~/.local/state/spore/theme.json`, which the
shell writes with the mode already resolved. Details in
[architecture](architecture.md#files-shellfilesqml).

## IPC

For scripts and the automated test, Files answers on the `files` target,
acting on the window that last had the focus:

```bash
quickshell ipc -p <spore's folder>/shell/files.qml call files <function> [argument]
```

| Function | Does |
|---|---|
| `open <path>` | Another window (what `spore-files` does when Files is already running) |
| `go <path>`, `back`, `forward`, `up` | Navigate (`recent:///` is Recent) |
| `filter <text>` | Filter (`""` clears it) |
| `setView <grid\|list>`, `toggleHidden` | Change the view, show the hidden files |
| `select <name>`, `toggle <name>`, `selectAll` | Select a file, add or take it away (Ctrl+click), select everything |
| `activate` | What Enter does: the selected file opens with its app, a folder in the window |
| `quickView` | Open or close the quick view |
| `turnPage <1\|-1>` | In the quick view of a PDF: the next page, or the one before |
| `copy`, `cut`, `paste`, `rename <name>`, `newFolder`, `trash` | What Ctrl+C, Ctrl+X, Ctrl+V, F2, Ctrl+Shift+N and Delete do |
| `answer <keep\|replace\|skip\|cancel\|delete>`, `cancel` | Answer what the window or a paste asks; stop a copy |
| `restore`, `purge`, `emptyTrash` | In the Trash: restore, delete for good (asks), empty it (asks) |
| `copyPath`, `terminal` | Copy the paths; a terminal in the open folder |
| `drop <folder\|trash> <auto\|copy\|move>` | The selection dropped there, as a drag would (auto: moves within a disk, copies to another) |
| `addFavorite <path>`, `removeFavorite <path>` | A folder added to the favorites, or taken away |
| `extract`, `compress` | The archives selected, each into a folder; the selection into a zip |
| `close` | Close the window |
| `state` | JSON: `windows`, `folder`, `count`, `total`, `thumbnails` (files with one), `view`, `showHidden`, `selected`, `names`, `preview` (what the quick view shows), `page` (a PDF's, as `3/12`), `listing` (an archive's, as `3 files in 1 folder · 2.1 MB extracted`), `playing`, `selectedCount`, `renaming`, `busy`, `progress`, `question`, `message` (the status line's error or note), `inTrash`, `favorites`, `clipboard` |
