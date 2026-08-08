---@type string, LibItemMovePrivate
local ADDON_NAME, Private = ...
Private = Private or {}
local Scheduler = { thread = nil, active = false }
Private.Scheduler = Scheduler

local frame = nil

--- Ensures hidden frame creation and script wiring for OnUpdate.
local function EnsureFrame()
    if not frame and _G.CreateFrame then
        frame = _G.CreateFrame("Frame")
        frame:Hide()
        frame:SetScript("OnUpdate", function(self, elapsed)
            Scheduler.Tick()
        end)
    end
end

--- Executes a single coroutine tick on frame update.
function Scheduler.Tick()
    if not Scheduler.active or not Scheduler.thread then
        if frame then frame:Hide() end
        return
    end

    if coroutine.status(Scheduler.thread) == "dead" then
        Scheduler.active = false
        Scheduler.thread = nil
        if frame then frame:Hide() end
        return
    end

    local success, err = coroutine.resume(Scheduler.thread)
    if not success then
        if Private.APIAdapter then
            Private.APIAdapter.ClearCursor()
        elseif _G.ClearCursor then
            _G.ClearCursor()
        end
        Scheduler.active = false
        Scheduler.thread = nil
        if frame then frame:Hide() end
        error("LibItemMove Coroutine Error: " .. tostring(err))
    end
end

--- Starts a new cooperative task thread.
--- @param func function Entry point function to run inside coroutine
--- @param ... any Arguments passed to func
function Scheduler.Start(func, ...)
    EnsureFrame()

    Scheduler.thread = coroutine.create(func)
    Scheduler.active = true
    if frame then frame:Show() end

    -- Initial step execution
    local success, err = coroutine.resume(Scheduler.thread, ...)
    if not success then
        if Private.APIAdapter then
            Private.APIAdapter.ClearCursor()
        elseif _G.ClearCursor then
            _G.ClearCursor()
        end
        Scheduler.active = false
        Scheduler.thread = nil
        if frame then frame:Hide() end
        error("LibItemMove Start Error: " .. tostring(err))
    end
end

--- Stops current scheduler thread and cleans up frame.
function Scheduler.Stop()
    Scheduler.active = false
    Scheduler.thread = nil
    if frame then frame:Hide() end
end

return Scheduler
