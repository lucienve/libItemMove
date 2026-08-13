---@type string, LibItemMovePrivate
local ADDON_NAME, Private = ...
Private = Private or {}
local Mover = {}
Private.Mover = Mover

local Utils = Private.Utils
local APIAdapter = Private.APIAdapter
local Scheduler = Private.Scheduler

--- Helper to trigger both per-move callback function and Ace3/CallbackHandler events
--- @param callback function? Direct per-move callback
--- @param dispatchGlobalEvent function? CallbackHandler dispatcher function
--- @param event CallbackEvent "PROGRESS" | "UPDATE_UI" | "TIMEOUT_ERROR" | "CURSOR_LOCKED_ERROR" | "PERMISSION_ERROR" | "DONE"
--- @param ... any Additional event payload parameters
local function NotifyCallback(callback, dispatchGlobalEvent, event, ...)
    if callback and type(callback) == "function" then
        pcall(callback, event, ...)
    end
    if dispatchGlobalEvent and type(dispatchGlobalEvent) == "function" then
        pcall(dispatchGlobalEvent, event, ...)
    end
end

--- Finds an eligible target empty slot that matches the item's specialty family.
--- @param itemString string|number
--- @param emptySlots SlotId[] List of available empty slot IDs
--- @param context MoveContext
--- @return SlotId? targetSlotId
function Mover.FindTargetSlot(itemString, emptySlots, context)
    local itemID = Utils.GetItemIdFromString(itemString)
    local itemFamily = APIAdapter.GetItemFamily(itemID)

    if Private.DebugLog then
        Private.DebugLog("FindTargetSlot(%s): itemID = %s, itemFamily = %s", tostring(itemString), tostring(itemID), tostring(itemFamily))
    end

    for idx, slotId in ipairs(emptySlots) do
        local tBag, tSlot = Utils.decode_bagslot(slotId)
        local bagFamily = context:GetBagFamily(tBag)
        local compatible = Utils.IsFamilyCompatible(itemFamily, bagFamily)

        if Private.DebugLog then
            Private.DebugLog("FindTargetSlot(%s): checking empty slot %d (bag %d, slot %d) with bagFamily = %s. Compatible = %s",
                tostring(itemString), idx, tBag, tSlot, tostring(bagFamily), tostring(compatible))
        end

        if compatible then
            if Private.DebugLog then
                Private.DebugLog("FindTargetSlot(%s): matched compatible slot %d (bag %d, slot %d). Removing from empty slots.",
                    tostring(itemString), idx, tBag, tSlot)
            end
            table.remove(emptySlots, idx)
            return slotId
        end
    end

    if Private.DebugLog then
        Private.DebugLog("FindTargetSlot(%s): failed to find any compatible empty slots!", tostring(itemString))
    end
    return nil
end

--- Threaded cooperative move runner loop (executed inside coroutine).
--- @param moveQueue MoveQueue Map of itemString to quantity
--- @param context MoveContext Move strategy context
--- @param callback function? Direct per-move callback
--- @param dispatchGlobalEvent function? CallbackHandler dispatcher
function Mover.MoveThread(moveQueue, context, callback, dispatchGlobalEvent)
    -- Cursor safety check: abort immediately if player is actively holding an item on cursor
    if APIAdapter.GetCursorInfo() ~= nil then
        NotifyCallback(callback, dispatchGlobalEvent, "CURSOR_LOCKED_ERROR")
        return
    end

    -- Permission guard check (e.g. Guild Bank tab permissions)
    if type(context.HasPermission) == "function" and not context:HasPermission() then
        NotifyCallback(callback, dispatchGlobalEvent, "PERMISSION_ERROR")
        return
    end

    local emptySlots = {}
    context:GetEmptySlots(emptySlots)

    local pending = {}

    -- Support both SlotIterator and SlotIdIterator spec naming
    local getIterator = function(ctx, itemStr)
        if type(ctx.SlotIterator) == "function" then
            return ctx:SlotIterator(itemStr)
        elseif type(ctx.SlotIdIterator) == "function" then
            return ctx:SlotIdIterator(itemStr)
        end
        return function() return nil end
    end

    -- Pair source items to move with destination target slots (Partial stacks first, empty slots second)
    for itemString, qtyToMove in pairs(moveQueue) do
        local remainingToMove = qtyToMove

        -- Step 1: Scan for existing partial stacks to consolidate
        local partialSlots = {}
        if type(context.GetPartialSlots) == "function" then
            context:GetPartialSlots(itemString, partialSlots)
        end



        for _, srcIdx, currentQty in getIterator(context, itemString) do
            local workingQty = currentQty
            if remainingToMove > 0 then
                -- Try to merge into partial target stacks first
                for pIdx, pData in ipairs(partialSlots) do
                    if remainingToMove > 0 and workingQty > 0 and pData.roomLeft > 0 then
                        local moveQty = math.min(workingQty, remainingToMove, pData.roomLeft)
                        table.insert(pending, {
                            src = srcIdx,
                            target = pData.slotId,
                            qty = moveQty,
                            endQty = math.max(workingQty - moveQty, 0),
                            item = itemString,
                            isPartial = true,
                            expectedDestQty = pData.currentQty + moveQty
                        })
                        remainingToMove = remainingToMove - moveQty
                        workingQty = workingQty - moveQty
                        pData.roomLeft = pData.roomLeft - moveQty
                    end
                end

                -- Step 2: Assign remaining quantity to empty slots
                if remainingToMove > 0 and workingQty > 0 then
                    local targetSlotId = Mover.FindTargetSlot(itemString, emptySlots, context)
                    if targetSlotId then
                        local moveQty = math.min(workingQty, remainingToMove)
                        table.insert(pending, {
                            src = srcIdx,
                            target = targetSlotId,
                            qty = moveQty,
                            endQty = math.max(workingQty - moveQty, 0),
                            item = itemString,
                            isPartial = false,
                            expectedDestQty = moveQty
                        })
                        remainingToMove = remainingToMove - moveQty
                        workingQty = workingQty - moveQty
                    end
                end
            end
        end
    end

    -- Process pending moves loop
    while next(pending) do
        local movedSlotId = nil

        -- Execute move operations
        for moveIndex, moveData in pairs(pending) do
            if APIAdapter.GetCursorInfo() then
                APIAdapter.ClearCursor()
            end

            -- Slot lock check: wait if source or target slot is locked in transit (with 5s timeout safety)
            local sBag, sSlot = Utils.decode_bagslot(moveData.src)
            local tBag, tSlot = Utils.decode_bagslot(moveData.target)
            local lockTimeout = ((_G.GetTime and _G.GetTime()) or os.time()) + 5
            local isTimedOut = false

            while (context.IsSourceSlotLocked and context:IsSourceSlotLocked(sBag, sSlot)) or
                  (context.IsTargetSlotLocked and context:IsTargetSlotLocked(tBag, tSlot)) do
                if ((_G.GetTime and _G.GetTime()) or os.time()) >= lockTimeout then
                    isTimedOut = true
                    break
                end
                coroutine.yield()
            end

            if isTimedOut then
                APIAdapter.ClearCursor()
                NotifyCallback(callback, dispatchGlobalEvent, "TIMEOUT_ERROR")
                return
            end

            -- Mid-loop cursor safety check right before issuing move call
            if APIAdapter.GetCursorInfo() ~= nil then
                APIAdapter.ClearCursor()
                NotifyCallback(callback, dispatchGlobalEvent, "CURSOR_LOCKED_ERROR")
                return
            end

            context:MoveSlot(moveData.src, moveData.target, moveData.qty)
            coroutine.yield() -- Yield to allow WoW client to process click/packet

            -- Stuck Cursor Recovery (up to 10 retries with item ID validation)
            local cursorType, cursorItemId = APIAdapter.GetCursorInfo()
            if cursorType == "item" then
                local retries = 0
                local expectedId = Utils.GetItemIdFromString(moveData.item)

                while APIAdapter.GetCursorInfo() == "item" and retries < 10 do
                    local _, cItemId = APIAdapter.GetCursorInfo()
                    if cItemId and expectedId and cItemId ~= expectedId then
                        -- Held item does not match expected target item; break to avoid dropping wrong item
                        break
                    end
                    context:PickupItem(tBag, tSlot) -- Retry drop click
                    coroutine.yield()
                    retries = retries + 1
                end
            end

            if context.isGuildBank then
                movedSlotId = moveIndex
                break -- Enforce Guild Bank throttling constraint: 1 move per yield cycle
            end
        end

        -- Transaction verification phase
        local didMove = false
        local now = (_G.GetTime and _G.GetTime()) or os.time()
        local timeout = now + 5 -- 5 second timeout window

        while not didMove and (((_G.GetTime and _G.GetTime()) or os.time()) < timeout) do
            for moveIndex, moveData in pairs(pending) do
                if not context.isGuildBank or moveIndex == movedSlotId then
                    local getSrcQty = context.GetSourceSlotQuantity or context.GetSlotQuantity
                    local getDestItemId = context.GetTargetSlotItemId or context.GetSlotItemId
                    local getDestQty = context.GetTargetSlotQuantity or context.GetSlotQuantity

                    local srcQtyOk = getSrcQty(context, moveData.src) <= moveData.endQty
                    local tBag, tSlot = Utils.decode_bagslot(moveData.target)
                    local expectedId = context:GetItemIdFromString(moveData.item)
                    local destItemIdOk = (getDestItemId(context, tBag, tSlot) == expectedId)
                    local destQtyOk = getDestQty(context, moveData.target) >= moveData.expectedDestQty
                    local cursorOk = APIAdapter.GetCursorInfo() == nil

                    if srcQtyOk and destItemIdOk and destQtyOk and cursorOk then
                        didMove = true
                        pending[moveIndex] = nil
                        NotifyCallback(callback, dispatchGlobalEvent, "PROGRESS", moveData.item, moveData.qty)
                    end
                end
            end

            if didMove then
                NotifyCallback(callback, dispatchGlobalEvent, "UPDATE_UI")
            end

            coroutine.yield() -- Wait for next frame / server packet update
        end

        if didMove and context.isGuildBank then
            local waitTime = ((_G.GetTime and _G.GetTime()) or os.time()) + 0.2
            while ((_G.GetTime and _G.GetTime()) or os.time()) < waitTime do
                coroutine.yield()
            end
        end

        -- Handle timeout failures
        if not didMove then
            for moveIndex, moveData in pairs(pending) do
                if not context.isGuildBank or moveIndex == movedSlotId then
                    local getSrcQty = context.GetSourceSlotQuantity or context.GetSlotQuantity
                    local getDestItemId = context.GetTargetSlotItemId or context.GetSlotItemId
                    local getDestQty = context.GetTargetSlotQuantity or context.GetSlotQuantity
                    local tBag, tSlot = Utils.decode_bagslot(moveData.target)
                    local sBag, sSlot = Utils.decode_bagslot(moveData.src)
                    Private.DebugLog("TIMEOUT DETAILS: Item=%s, Qty=%s, Src=[%s,%s] (Qty left=%s, expected end=%s), Dest=[%s,%s] (ItemID=%s, Qty=%s, expected=%s), Cursor=%s",
                        tostring(moveData.item), tostring(moveData.qty),
                        tostring(sBag), tostring(sSlot), tostring(getSrcQty(context, moveData.src)), tostring(moveData.endQty),
                        tostring(tBag), tostring(tSlot), tostring(getDestItemId(context, tBag, tSlot)), tostring(getDestQty(context, moveData.target)), tostring(moveData.expectedDestQty),
                        tostring(APIAdapter.GetCursorInfo())
                    )
                end
            end
            APIAdapter.ClearCursor()
            NotifyCallback(callback, dispatchGlobalEvent, "TIMEOUT_ERROR")
            break
        end
    end

    NotifyCallback(callback, dispatchGlobalEvent, "DONE")
end

--- Initiates a move task.
--- @param moveQueue MoveQueue Map of itemString to quantity to move
--- @param context MoveContext Strategy context
--- @param callback function? Per-move callback function
--- @param dispatchGlobalEvent function? CallbackHandler dispatcher function
function Mover.StartMove(moveQueue, context, callback, dispatchGlobalEvent)
    Scheduler.Start(Mover.MoveThread, moveQueue, context, callback, dispatchGlobalEvent)
end

--- Threaded cooperative multi-tab move runner loop.
--- @param moveQueue table Map of tabIndex to single-tab MoveQueue
--- @param context MoveContext Move strategy context
--- @param callback function? Direct per-move callback
--- @param dispatchGlobalEvent function? CallbackHandler dispatcher
function Mover.MoveMultiTabThread(moveQueue, context, callback, dispatchGlobalEvent)
    -- Cursor safety check: abort immediately if player is actively holding an item on cursor
    if APIAdapter.GetCursorInfo() ~= nil then
        NotifyCallback(callback, dispatchGlobalEvent, "CURSOR_LOCKED_ERROR")
        return
    end

    -- Collect and sort tab indices
    local tabs = {}
    for tabIndex, _ in pairs(moveQueue) do
        table.insert(tabs, tabIndex)
    end
    table.sort(tabs)

    for _, tabIndex in ipairs(tabs) do
        local tabQueue = moveQueue[tabIndex]

        -- Switch tab if needed
        local currentTab = (_G.GetCurrentGuildBankTab and _G.GetCurrentGuildBankTab()) or 1
        if currentTab ~= tabIndex then
            local tabLoaded = false
            local eventFrame = nil
            if _G.CreateFrame then
                eventFrame = _G.CreateFrame("Frame")
                eventFrame:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
                eventFrame:SetScript("OnEvent", function(self, event)
                    tabLoaded = true
                end)
            else
                tabLoaded = true -- Fallback for environments without CreateFrame
            end

            if _G.SetCurrentGuildBankTab then
                _G.SetCurrentGuildBankTab(tabIndex)
            end
            if _G.QueryGuildBankTab then
                _G.QueryGuildBankTab(tabIndex)
            end

            -- Yield until tab loaded or timeout (2 seconds)
            local timeout = ((_G.GetTime and _G.GetTime()) or os.time()) + 2
            while not tabLoaded and ((_G.GetTime and _G.GetTime()) or os.time()) < timeout do
                coroutine.yield()
            end

            if eventFrame then
                eventFrame:UnregisterAllEvents()
                eventFrame:Hide()
            end
        end

        -- Run the single-tab move inside the current coroutine
        local tabFailed = false
        local function innerCallback(event, ...)
            if event == "DONE" then
                -- Single-tab finished successfully
            elseif event == "TIMEOUT_ERROR" or event == "CURSOR_LOCKED_ERROR" or event == "PERMISSION_ERROR" then
                tabFailed = true
                NotifyCallback(callback, dispatchGlobalEvent, event, ...)
            else
                NotifyCallback(callback, dispatchGlobalEvent, event, ...)
            end
        end

        Mover.MoveThread(tabQueue, context, innerCallback, nil)

        if tabFailed then
            return -- Abort sequence if an error occurred
        end
    end

    NotifyCallback(callback, dispatchGlobalEvent, "DONE")
end

--- Initiates a multi-tab move task.
--- @param moveQueue table Map of tabIndex to single-tab MoveQueue
--- @param context MoveContext Strategy context
--- @param callback function? Per-move callback function
--- @param dispatchGlobalEvent function? CallbackHandler dispatcher function
function Mover.StartMultiTabMove(moveQueue, context, callback, dispatchGlobalEvent)
    Scheduler.Start(Mover.MoveMultiTabThread, moveQueue, context, callback, dispatchGlobalEvent)
end

return Mover
