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

# Linux only. The whole mail and backup pipeline lives on phoenix: the Maildir
# is there, the mailsync systemd timers that fill it have no launchd
# counterpart, and the T9 external drive both backup scripts write to is
# plugged in there -- which is why .zshrc exports MAIL_BACKUP_REPO under
# /run/media only on Linux. Reading mail on the Mac means ssh'ing over.
#
# libsecret is the reason this cannot be a soft preference: mail-backup and
# drive-backup take their restic password from `secret-tool`, and mbsync and
# msmtp take the Gmail App Password from it too. That is the Linux login
# keyring. The Mac equivalent is the system Keychain, which none of these
# scripts speak.
if OS.linux?
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
  # Google Drive backups (drive-backup). Photos deliberately does NOT go
  # through rclone -- the Photos API strips EXIF location and will not serve
  # originals, so that one has to come from Takeout.
  brew "rclone"
end

# macOS only (no Linux bottles available)
if OS.mac?
  # Dropbox and Obsidian are deliberately absent. They are installed by hand
  # on this machine, so listing them here only made `brew bundle` fight the
  # existing installs -- `check` reported them unsatisfied whatever their real
  # state. On Ubuntu they come from ubuntu/provision.sh instead: Dropbox from
  # its signed apt repo, Obsidian from the desktop .deb channel. So neither
  # machine wants them here, for opposite reasons.
  #
  # The terminal, which is the one GUI app that does come from Homebrew. It
  # only ever runs here: phoenix is reached over ssh from this machine and has
  # no terminal emulator of its own, so there is deliberately no kitty in
  # ubuntu/provision.sh. The kitty under ~/.local/share/kitty-ssh-kitten on
  # phoenix is payload the `kitten ssh` command pushes there for terminfo, not
  # an install to manage.
  cask "kitty"
  # Required for tmux copy/paste on macOS
  brew "reattach-to-user-namespace"
  # https://github.com/zerowidth/zoom-calendar.alfredworkflow
  brew "ical-buddy"
end
