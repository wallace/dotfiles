-- ~/.hammerspoon/voice-memo-pipeline.lua
--
-- Watches for the IC Recorder USB volume to mount, then syncs audio files
-- into the Dropbox watch folder. After a successful sync the volume is ejected.
--
-- Wire-up: add this line to ~/.hammerspoon/init.lua
--   require("voice-memo-pipeline")
--
-- Then reload Hammerspoon (menu bar → Reload Config) and plug in the recorder.

local M = {}

-- ── Config ───────────────────────────────────────────────────────────────

-- Substring match against the mounted volume path. Sony devices typically
-- mount as "/Volumes/IC RECORDER" (sometimes with a numeric suffix if a
-- volume with that name already exists).
local VOLUME_NAME_PATTERN = "IC RECORDER"

local SYNC_SCRIPT       = os.getenv("HOME") .. "/bin/voice-pipeline/sync-ic-recorder.sh"
local EJECT_AFTER_SYNC  = true   -- set false if you'd rather unmount by hand
local NOTIFY_ON_SUCCESS = true

-- ── Implementation ───────────────────────────────────────────────────────

local function notify(title, msg)
    hs.notify.new({
        title = title,
        informativeText = msg,
        withdrawAfter = 5,
    }):send()
end

local function eject(volumePath)
    hs.task.new("/usr/sbin/diskutil", function(code)
        if code == 0 then
            notify("IC Recorder", "Safe to unplug.")
        else
            notify("IC Recorder", "Eject failed — unmount manually.")
        end
    end, { "eject", volumePath }):start()
end

local function sync(volumePath)
    notify("Voice Memo Pipeline", "Syncing from " .. volumePath .. " …")

    local task = hs.task.new(SYNC_SCRIPT, function(exitCode, stdOut, stdErr)
        if exitCode == 0 then
            if NOTIFY_ON_SUCCESS then
                notify("Voice Memo Pipeline", "Sync complete.")
            end
            if EJECT_AFTER_SYNC then eject(volumePath) end
        else
            local msg = (stdErr ~= nil and stdErr ~= "") and stdErr
                     or ("Exit " .. tostring(exitCode))
            notify("Voice Memo Sync FAILED", msg)
        end
    end, { volumePath })

    task:start()
end

M.watcher = hs.fs.volume.new(function(event, info)
    if event ~= hs.fs.volume.didMount then return end
    local path = info.path or ""
    if path:match(VOLUME_NAME_PATTERN) then
        sync(path)
    end
end)

M.watcher:start()

return M
