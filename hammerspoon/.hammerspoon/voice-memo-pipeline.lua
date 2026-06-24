-- ~/.hammerspoon/voice-memo-pipeline.lua
--
-- Watches for the IC Recorder USB volume to mount, then syncs audio files into
-- the Dropbox watch folder. After a successful sync the volume is ejected —
-- UNLESS auto-eject is turned off, so you can keep it mounted to clear space
-- on the device by hand.
--
-- Auto-eject is toggled from a menu-bar item and the choice persists across
-- reloads / reboots (hs.settings):
--   ⏏️  = will auto-eject after sync
--   📌  = stay mounted after sync   (+ "Eject now" when you're done)
--
-- Wire-up: add to ~/.hammerspoon/init.lua
--   require("voice-memo-pipeline")
-- then Reload Config and plug in the recorder.

local M = {}

-- ── Config ───────────────────────────────────────────────────────────────
local VOLUME_NAME_PATTERN = "IC RECORDER"
local SYNC_SCRIPT         = os.getenv("HOME") .. "/bin/voice-pipeline/sync-ic-recorder.sh"
local NOTIFY_ON_SUCCESS   = true
local DEFAULT_AUTO_EJECT  = true                 -- value before you ever toggle it
local SETTING_KEY         = "voiceMemoPipeline.autoEject"

-- ── State ────────────────────────────────────────────────────────────────
local lastVolumePath = nil                       -- remembered for "Eject now"
local menubar                                    -- forward declaration
local refreshMenu                                -- forward declaration

local function autoEjectEnabled()
    local v = hs.settings.get(SETTING_KEY)
    if v == nil then return DEFAULT_AUTO_EJECT end
    return v
end

local function setAutoEject(v) hs.settings.set(SETTING_KEY, v) end

-- ── Implementation ───────────────────────────────────────────────────────
local function notify(title, msg)
    hs.notify.new({ title = title, informativeText = msg, withdrawAfter = 6 }):send()
end

local function eject(volumePath)
    if not volumePath then
        notify("IC Recorder", "No recorder volume known to eject.")
        return
    end
    hs.task.new("/usr/sbin/diskutil", function(code)
        if code == 0 then
            notify("IC Recorder", "Safe to unplug.")
            lastVolumePath = nil
            refreshMenu()
        else
            notify("IC Recorder", "Eject failed — unmount manually.")
        end
    end, { "eject", volumePath }):start()
end

refreshMenu = function()
    if not menubar then return end
    local on = autoEjectEnabled()
    menubar:setTitle(on and "⏏️" or "📌")
    menubar:setTooltip(on
        and "IC Recorder: auto-eject after sync"
        or  "IC Recorder: stay mounted after sync (clear space, then eject)")
    menubar:setMenu({
        { title = "Auto-eject after sync",  checked = on,
          fn = function() setAutoEject(true);  refreshMenu() end },
        { title = "Stay mounted after sync", checked = not on,
          fn = function() setAutoEject(false); refreshMenu() end },
        { title = "-" },
        { title = "Eject now", disabled = (lastVolumePath == nil),
          fn = function() eject(lastVolumePath) end },
    })
end

local function sync(volumePath)
    notify("Voice Memo Pipeline", "Syncing from " .. volumePath .. " …")
    local task = hs.task.new(SYNC_SCRIPT, function(exitCode, stdOut, stdErr)
        if exitCode == 0 then
            if autoEjectEnabled() then
                if NOTIFY_ON_SUCCESS then notify("Voice Memo Pipeline", "Sync complete.") end
                eject(volumePath)
            else
                notify("Voice Memo Pipeline",
                    "Sync complete — recorder still mounted. Clear space, then eject from the menu bar (📌 → Eject now).")
            end
        else
            local msg = (stdErr ~= nil and stdErr ~= "") and stdErr or ("Exit " .. tostring(exitCode))
            notify("Voice Memo Sync FAILED", msg)
        end
    end, { volumePath })
    task:start()
end

M.watcher = hs.fs.volume.new(function(event, info)
    if event ~= hs.fs.volume.didMount then return end
    local path = info.path or ""
    if path:match(VOLUME_NAME_PATTERN) then
        lastVolumePath = path
        refreshMenu()
        sync(path)
    end
end)
M.watcher:start()

menubar = hs.menubar.new()
M.menubar = menubar
refreshMenu()

return M
