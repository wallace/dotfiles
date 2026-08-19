#!/bin/bash
#
# Author:  Eric Gebhart
#
# Purpose:  To be called by mutt as indicated by .mailcap to handle mail attachments.
#
# Function: Copy the given file to a temporary directory so mutt
#           Won't delete it before it is read by the application.
#
#           Along the way, discern the file type or use the type
#           That is given.
#
#           Finally hand the file to xdg-open, or to the program named by
#           the third argument if one is given.
#
#
# Arguments:
#
#     $1 is the file
#     $2 is the type - for those times when file magic isn't enough.
#                      I frequently get html mail that has no extension
#                      and file can't figure out what it is.
#
#                      Set to '-' if you don't want the type to be discerned.
#                      Many applications can sniff out the type on their own.
#                      And they do a better job of it too.
#
#                      Open Office and MS Office for example.
#
#     $3 is open with.  The program to hand the file to instead of letting
#                      xdg-open pick, as in 'libreoffice foo.xls'.
#
# Examples:  These are typical .mailcap entries which use this program.
#
#     Image/JPEG; /Users/vdanen/.mutt/view_attachment %s
#     Image/PNG; /Users/vdanen/.mutt/view_attachment %s
#     Image/GIF; /Users/vdanen/.mutt/view_attachment %s
#
#     Application/PDF; /Users/vdanen/.mutt/view_attachment %s
#
#         #This HTML example passes the type because file doesn't always work and
#         #there aren't always extensions.
#
#     text/html; /Users/vdanen/.mutt/view_attachment %s html
#
#         # If your Start OpenOffice.org.app is spelled with a space like this one, <--
#         # then you'll need to precede the space with a \ .  I found that too painful
#         # and renamed it with an _.
#
#     Application/vnd.ms-excel; ~/.mutt/view_attachment.sh %s "-" libreoffice
#     Application/msword; ~/.mutt/view_attachment.sh %s "-" libreoffice
#
#
# Debugging:  If you have problems run neomutt with MUTT_ATTACH_DEBUG=yes.  That will
#             cause a debug file to be written alongside the copied attachment in
#             $HOME/.tmp/mutt_attach/view.XXXXXX/debug so you can see what is going on.
#
# See Also:  The man pages for open, file, basename
#

set -u

# Per-invocation tmp dir under the user's home — avoids the cross-invocation
# rm -f race the old script had (two attachments opened in parallel would
# clobber each other), and stays in $HOME rather than world-writable /tmp.
base_tmp="$HOME/.tmp/mutt_attach"
mkdir -p "$base_tmp"

# Nothing else ever reaps these, so each viewing would leak a directory forever.
# A day is well past the point where any viewer we detached below is still
# reading its copy, so anything older is safe to drop.
find "$base_tmp" -mindepth 1 -maxdepth 1 -name 'view.*' -mtime +0 \
    -exec rm -rf -- {} + 2>/dev/null

tmpdir=$(mktemp -d "$base_tmp/view.XXXXXX")

debug_file="$tmpdir/debug"
# Off unless asked for: the debug file is written into the per-invocation dir,
# so leaving it on means every attachment ever opened leaves litter behind.
debug="${MUTT_ATTACH_DEBUG:-no}"

src="${1:-}"
type="${2:-}"
open_with="${3:-}"

if [ -z "$src" ]; then
    echo "usage: $0 <file> [type|-] [open-with-app]" >&2
    exit 1
fi

# Mutt puts everything in /tmp by default.
# This gets the basic filename from the full pathname.
filename=$(basename -- "$src")

# get rid of the extension and save the name for later.
file="${filename%.*}"

if [ "$debug" = "yes" ]; then
    {
        echo "1: $src  2: $type  3: $open_with"
        echo "Filename: $filename"
        echo "File: $file"
        echo "==========================="
    } > "$debug_file"
fi

# if the type is empty then try to figure it out.
if [ -z "$type" ]; then
    type=$(file -bi -- "$src" | cut -d"/" -f2)
fi

# if the type is '-' then we don't want to mess with type.
# Otherwise we are rebuilding the name.  Either from the
# type that was passed in or from the type we discerned.
if [ "$type" = "-" ]; then
    newfile="$filename"
else
    newfile="$file.$type"
fi

newfile="$tmpdir/$newfile"

# Copy the file to our new spot so mutt can't delete it
# before the app has a chance to view it.
cp -- "$src" "$newfile"

if [ "$debug" = "yes" ]; then
    {
        echo "File: $file TYPE: $type"
        echo "Newfile: $newfile"
        echo "Open With: $open_with"
    } >> "$debug_file"
fi

# If there's no 'open with' then let the desktop's default handler decide.
# Otherwise we've been told exactly which program to use.
#
# Detached, because neomutt blocks until this script returns and there is no
# reason to freeze the mail client while a PDF viewer is open. The copy above
# is what makes that safe: neomutt is free to delete its own temp file.
if [ -z "$open_with" ]; then
    xdg-open "$newfile" >/dev/null 2>&1 &
else
    "$open_with" "$newfile" >/dev/null 2>&1 &
fi
