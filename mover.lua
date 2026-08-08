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

    for idx, slotId in ipairs(emptySlots) do
        local tBag, _ = Utils.decode_bagslot(slotId)
        local bagFamily = APIAdapter.GetBagItemFamily(tBag)

        if Utils.IsFamilyCompatible(itemFamily, bagFamily) then
            table.remove(emptySlots, idx)
            return slotId
        end
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
            if remainingToMove > 0 then
                -- Try to merge into partial target stacks first
                for pIdx, pData in ipairs(partialSlots) do
                    if remainingToMove > 0 and pData.roomLeft > 0 then
                        local moveQty = math.min(currentQty, remainingToMove, pData.roomLeft)
                        pending[srcIdx] = {
                            target = pData.slotId,
                            qty = moveQty,
                            endQty = math.max(currentQty - moveQty, 0),
                            item = itemString,
                            isPartial = true,
                            initiated = false
                        }
                        remainingToMove = remainingToMove - moveQty
                        pData.roomLeft = pData.roomLeft - moveQty
                    end
                end

                -- Step 2: Assign remaining quantity to empty slots
                if remainingToMove > 0 and not pending[srcIdx] then
                    local targetSlotId = Mover.FindTargetSlot(itemString, emptySlots, context)
                    if targetSlotId then
                        local moveQty = math.min(currentQty, remainingToMove)
                        pending[srcIdx] = {
                            target = targetSlotId,
                            qty = moveQty,
                            endQty = math.max(currentQty - moveQty, 0),
                            item = itemString,
                            isPartial = false,
                            initiated = false
                        }
                        remainingToMove = remainingToMove - moveQty
                    end
                end
            end
        end
    end

    -- Process pending moves loop
    while next(pending) do
        local movedSlotId = nil

        -- Execute move operations
        for srcSlotId, moveData in pairs(pending) do
            if not moveData.initiated then
                if APIAdapter.GetCursorInfo() then
                    APIAdapter.ClearCursor()
                end

                -- Slot lock check: wait if source or target slot is locked in transit (with 2s timeout safety)
                local sBag, sSlot = Utils.decode_bagslot(srcSlotId)
                local tBag, tSlot = Utils.decode_bagslot(moveData.target)
                local lockTimeout = ((_G.GetTime and _G.GetTime()) or os.time()) + 2
                local isTimedOut = false

                while context:IsSlotLocked(sBag, sSlot) or context:IsSlotLocked(tBag, tSlot) do
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

                context:MoveSlot(srcSlotId, moveData.target, moveData.qty)
                moveData.initiated = true
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
                    movedSlotId = srcSlotId
                    break -- Enforce Guild Bank throttling constraint: 1 move per yield cycle
                end
            end
        end

        -- Transaction verification phase
        local didMove = false
        local now = (_G.GetTime and _G.GetTime()) or os.time()
        local timeout = now + 2 -- 2 second timeout window

        while not didMove and (((_G.GetTime and _G.GetTime()) or os.time()) < timeout) do
            for srcSlotId, moveData in pairs(pending) do
                if not context.isGuildBank or srcSlotId == movedSlotId then
                    local srcQtyOk = context:GetSlotQuantity(srcSlotId) <= moveData.endQty
                    local tBag, tSlot = Utils.decode_bagslot(moveData.target)
                    local expectedId = context:GetItemIdFromString(moveData.item)
                    local destItemIdOk = (context:GetSlotItemId(tBag, tSlot) == expectedId)

                    if srcQtyOk and destItemIdOk then
                        didMove = true
                        pending[srcSlotId] = nil
                        NotifyCallback(callback, dispatchGlobalEvent, "PROGRESS", moveData.item, moveData.qty)
                    end
                end
            end

            if didMove then
                NotifyCallback(callback, dispatchGlobalEvent, "UPDATE_UI")
            end

            coroutine.yield() -- Wait for next frame / server packet update
        end

        -- Handle timeout failures
        if not didMove then
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

return Mover
