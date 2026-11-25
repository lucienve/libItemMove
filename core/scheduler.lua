---@type string, LibItemMovePrivate
local _, Private = ...
Private = Private or {}
local Scheduler = { thread = nil, active = false }
Private.Scheduler = Scheduler

local APIAdapter = Private.APIAdapter

local frame = nil

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
        APIAdapter.ClearCursor()
        Scheduler.active = false
        Scheduler.thread = nil
        if frame then frame:Hide() end
        error("LibItemMove Coroutine Error: " .. tostring(err))
    end
end

--- Ensures hidden frame creation and script wiring for OnUpdate.
local function EnsureFrame()
    if not frame and _G.CreateFrame then
        frame = _G.CreateFrame("Frame")
        frame:Hide()
        frame:SetScript("OnUpdate", Scheduler.Tick)
    end
end

--- Starts a new cooperative task thread. Safely rejects concurrent start calls while active.
--- @param func function Entry point function to run inside coroutine
--- @param ... any Arguments passed to func
function Scheduler.Start(func, ...)
    if Scheduler.active and Scheduler.thread and coroutine.status(Scheduler.thread) ~= "dead" then
        error("LibItemMove: A move transaction is already in progress.")
    end

    EnsureFrame()

    Scheduler.thread = coroutine.create(func)
    Scheduler.active = true
    if frame then frame:Show() end

    -- Initial step execution
    local success, err = coroutine.resume(Scheduler.thread, ...)
    if not success then
        APIAdapter.ClearCursor()
        Scheduler.active = false
        Scheduler.thread = nil
        if frame then frame:Hide() end
        error("LibItemMove Start Error: " .. tostring(err))
    end
end
