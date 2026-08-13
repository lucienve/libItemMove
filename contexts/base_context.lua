---@type string, LibItemMovePrivate
local ADDON_NAME, Private = ...
Private = Private or {}
local BaseContext = {}
Private.BaseContext = BaseContext

local Utils = Private.Utils
local APIAdapter = Private.APIAdapter

BaseContext.__index = BaseContext

--- Creates a new instance of a move strategy context.
--- @param o table?
--- @return MoveContext
function BaseContext:New(o)
    o = o or {}
    setmetatable(o, self)
    return o
end

--- Returns true if the player currently has permission to move items in this context.
--- @return boolean hasPermission
function BaseContext:HasPermission()
    return true
end

--- Parses numeric item ID from item ID integer or item string format.
--- @param itemString string|number
--- @return number? itemId
function BaseContext:GetItemIdFromString(itemString)
    return Utils.GetItemIdFromString(itemString)
end

--- Checks if a container slot is currently locked in transit.
--- @param bag number
--- @param slot number
--- @return boolean isLocked
function BaseContext:IsSlotLocked(bag, slot)
    local info = APIAdapter.GetContainerItemInfo(bag, slot)
    return info and info.isLocked or false
end

--- Checks if the source slot is currently locked in transit.
--- @param bag number
--- @param slot number
--- @return boolean isLocked
function BaseContext:IsSourceSlotLocked(bag, slot)
    return self:IsSlotLocked(bag, slot)
end

--- Checks if the target slot is currently locked in transit.
--- @param bag number
--- @param slot number
--- @return boolean isLocked
function BaseContext:IsTargetSlotLocked(bag, slot)
    return self:IsSlotLocked(bag, slot)
end

--- Returns item stack count at target slot ID.
--- @param slotId SlotId
--- @return number count
function BaseContext:GetSlotQuantity(slotId)
    local bag, slot = Utils.decode_bagslot(slotId)
    local info = APIAdapter.GetContainerItemInfo(bag, slot)
    return info and info.stackCount or 0
end

--- Returns item stack count at source slot ID.
--- @param slotId SlotId
--- @return number count
function BaseContext:GetSourceSlotQuantity(slotId)
    return self:GetSlotQuantity(slotId)
end

--- Returns item stack count at target slot ID.
--- @param slotId SlotId
--- @return number count
function BaseContext:GetTargetSlotQuantity(slotId)
    return self:GetSlotQuantity(slotId)
end

--- Returns numeric item ID at bag & slot.
--- @param bag number
--- @param slot number
--- @return number? itemID
function BaseContext:GetSlotItemId(bag, slot)
    return APIAdapter.GetContainerItemID(bag, slot)
end

--- Returns numeric item ID at source bag & slot.
--- @param bag number
--- @param slot number
--- @return number? itemID
function BaseContext:GetSourceSlotItemId(bag, slot)
    return self:GetSlotItemId(bag, slot)
end

--- Returns numeric item ID at target bag & slot.
--- @param bag number
--- @param slot number
--- @return number? itemID
function BaseContext:GetTargetSlotItemId(bag, slot)
    return self:GetSlotItemId(bag, slot)
end

--- Helper function to safely query slot count across WoW versions.
--- @param bag number Container ID
--- @return number numSlots
local function GetContainerNumSlots(bag)
    local cContainer = _G["C_Container"]
    if cContainer and cContainer.GetContainerNumSlots then
        return cContainer.GetContainerNumSlots(bag) or 0
    end
    local legacyGetNumSlots = _G["GetContainerNumSlots"]
    if legacyGetNumSlots then
        return legacyGetNumSlots(bag) or 0
    end
    return 0
end

--- Shared helper to scan containers and retrieve empty slots sorted by family (specialty first).
--- @param containers number[] List of bag/container IDs to scan
--- @param emptySlotIdsTable SlotId[] Destination array to append packed SlotIds
function BaseContext:ScanEmptySlots(containers, emptySlotIdsTable)
    local specialtySlots = {}
    local generalSlots = {}

    if Private.DebugLog then
        Private.DebugLog("ScanEmptySlots: scanning %d containers...", #containers)
    end

    for _, bag in ipairs(containers) do
        local bagFamily = APIAdapter.GetBagItemFamily(bag)
        local numSlots = GetContainerNumSlots(bag)

        if Private.DebugLog then
            Private.DebugLog("ScanEmptySlots: bag %d has family = %s, total slots = %d", bag, tostring(bagFamily), numSlots)
        end

        local emptyInBag = 0
        for slot = 1, numSlots do
            local info = APIAdapter.GetContainerItemInfo(bag, slot)
            if not info or info.stackCount == 0 then
                local slotId = Utils.encode_bagslot(bag, slot)
                emptyInBag = emptyInBag + 1
                if bagFamily ~= 0 then
                    table.insert(specialtySlots, slotId)
                else
                    table.insert(generalSlots, slotId)
                end
            end
        end

        if Private.DebugLog then
            Private.DebugLog("ScanEmptySlots: bag %d had %d empty slots", bag, emptyInBag)
        end
    end

    if Private.DebugLog then
        Private.DebugLog("ScanEmptySlots: finished scanning. Specialty empty slots found: %d, General empty slots found: %d",
            #specialtySlots, #generalSlots)
    end

    -- Specialized bags first, general bags second
    for _, slotId in ipairs(specialtySlots) do
        table.insert(emptySlotIdsTable, slotId)
    end
    for _, slotId in ipairs(generalSlots) do
        table.insert(emptySlotIdsTable, slotId)
    end
end

--- Shared helper to scan containers for partially filled stacks of the target item.
--- @param containers number[] List of bag/container IDs to scan
--- @param itemString string|number Target item identifier
--- @param partialSlotsTable table[] Destination array to append partial slot data { slotId, currentQty, roomLeft }
function BaseContext:ScanPartialSlots(containers, itemString, partialSlotsTable)
    local itemID = Utils.GetItemIdFromString(itemString)
    if not itemID then return end

    local maxStack = Utils.GetItemMaxStack(itemID)
    if maxStack <= 1 then return end -- Non-stackable items have no partial stacks

    for _, bag in ipairs(containers) do
        local bagFamily = APIAdapter.GetBagItemFamily(bag)
        local itemFamily = APIAdapter.GetItemFamily(itemID)

        if Utils.IsFamilyCompatible(itemFamily, bagFamily) then
            local numSlots = GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local info = APIAdapter.GetContainerItemInfo(bag, slot)
                if info and info.stackCount > 0 and info.stackCount < maxStack then
                    if Utils.IsItemMatching(itemString, info) then
                        local slotId = Utils.encode_bagslot(bag, slot)
                        table.insert(partialSlotsTable, {
                            slotId = slotId,
                            currentQty = info.stackCount,
                            roomLeft = maxStack - info.stackCount
                        })
                    end
                end
            end
        end
    end
end

--- Default implementation for GetPartialSlots delegating to ScanPartialSlots.
--- @param itemString string|number
--- @param partialSlotsTable table[]
function BaseContext:GetPartialSlots(itemString, partialSlotsTable)
    -- Default base implementation scans target containers defined in subclasses
end

--- Shared iterator over containers for matching itemString.
--- @param containers number[] List of container IDs to scan
--- @param itemString string|number Target item identifier
--- @return fun(): number?, SlotId?, number? Iterator function returning (index, slotId, currentQty)
function BaseContext:ScanSourceSlots(containers, itemString)
    local slotList = {}

    for _, bag in ipairs(containers) do
        local numSlots = GetContainerNumSlots(bag)

        for slot = 1, numSlots do
            local info = APIAdapter.GetContainerItemInfo(bag, slot)
            if info and info.stackCount > 0 and Utils.IsItemMatching(itemString, info) then
                table.insert(slotList, {
                    slotId = Utils.encode_bagslot(bag, slot),
                    qty = info.stackCount
                })
            end
        end
    end

    local i = 0
    return function()
        i = i + 1
        if slotList[i] then
            return i, slotList[i].slotId, slotList[i].qty
        end
        return nil
    end
end

--- Alias for SlotIterator matching specification in item_movement_instructions.md.
--- @param itemString string|number Target item identifier
--- @return fun(): number?, SlotId?, number?
function BaseContext:SlotIdIterator(itemString)
    if type(self.SlotIterator) == "function" then
        return self:SlotIterator(itemString)
    end
    return function() return nil end
end

return BaseContext
