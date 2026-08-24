# Core tools (cross-platform)
brew "pure"
brew "stow"
brew "rbenv"
brew "nodenv"
brew "readline"
brew "vim"
brew "git"
brew "zsh"
brew "tmux"
brew "fzf"
brew "gh"
brew "ripgrep"
brew "adr-tools"
brew "git-delta"
brew "direnv"
# brew "octo-cli/octo/octo"
brew "exiftool"
brew "imagemagick"
brew "ctags"
brew "neovim"

# github sql primer
brew "git-lfs"

# Mail: neomutt reads a local Maildir that isync (mbsync) fills from Gmail,
# notmuch indexes, and msmtp sends through. w3m renders HTML mail via
# ~/.mutt/mailcap; libsecret provides secret-tool, which holds the Gmail App
# Password that both mbsync and msmtp read.
brew "neomutt"
brew "urlview"
brew "w3m"
brew "libsecret"
brew "notmuch"
brew "isync"
brew "msmtp"
# Backups of ~/.mail. Once old mail is deleted from Gmail to reclaim Google
# storage, the local Maildir stops having a second copy anywhere.
brew "restic"
# Google Drive backups (drive-backup). Photos deliberately does NOT go through
# rclone -- the Photos API strips EXIF location and will not serve originals,
# so that one has to come from Takeout.
brew "rclone"

# macOS only (no Linux bottles available)
if OS.mac?
  # GUI apps. On Ubuntu these come from ubuntu/provision.sh instead: Dropbox
  # from its signed apt repo, Obsidian from Obsidian's own .deb, since casks
  # are macOS-only and Linuxbrew has neither.
  cask "dropbox"
  cask "obsidian"
  # Required for tmux copy/paste on macOS
  brew "reattach-to-user-namespace"
  # https://github.com/zerowidth/zoom-calendar.alfredworkflow
  brew "ical-buddy"
end
