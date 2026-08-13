---@type string, LibItemMovePrivate
local ADDON_NAME, Private = ...
Private = Private or {}
local Utils = {}
Private.Utils = Utils

Utils.SLOT_ID_MULTIPLIER = 1000

--- Packs a separate bag index and slot index into a single packed SlotId integer.
--- @param bag number Container/Bag ID
--- @param slot number Slot index within container
--- @return SlotId slotId Packed integer (bag * 1000 + slot)
function Utils.encode_bagslot(bag, slot)
    if not bag or not slot then return 0 end
    return bag * Utils.SLOT_ID_MULTIPLIER + slot
end

--- Unpacks a packed SlotId integer into constituent bag and slot numbers.
--- Note: Bag IDs can be negative in WoW (e.g. BANK_CONTAINER = -1, REAGENTBANK_CONTAINER = -3).
--- @param slotId SlotId Packed integer
--- @return number bag Container/Bag ID
--- @return number slot Slot index
function Utils.decode_bagslot(slotId)
    if not slotId then return 0, 0 end
    local bag = math.floor(slotId / Utils.SLOT_ID_MULTIPLIER)
    local slot = slotId % Utils.SLOT_ID_MULTIPLIER
    return bag, slot
end

--- Extracts the numeric item ID from various item representation formats (ID integer, item string, or link).
--- @param itemInput string|number Item ID, item string ("i:12345"), or item link
--- @return number? itemId Numeric Item ID if resolved
function Utils.GetItemIdFromString(itemInput)
    if type(itemInput) == "number" then
        return itemInput
    end
    if type(itemInput) ~= "string" then
        return nil
    end

    -- Match "i:12345" or "item:12345"
    local idStr = itemInput:match("item:(%d+)") or itemInput:match("i:(%d+)") or itemInput:match("^(%d+)$")
    if idStr then
        return tonumber(idStr)
    end
    return nil
end

--- Determines whether an item input matches a container slot's item info.
--- Supports matching base numeric Item ID as well as exact item string/link variants.
--- @param itemInput string|number Target item requested
--- @param slotInfo table Container slot info from GetContainerItemInfo
--- @return boolean isMatch True if item matches
function Utils.IsItemMatching(itemInput, slotInfo)
    if not itemInput or not slotInfo or not slotInfo.itemID then
        return false
    end

    local targetId = Utils.GetItemIdFromString(itemInput)
    if targetId ~= slotInfo.itemID then
        return false
    end

    -- If itemInput is a full item link or complex string (containing suffix/bonus IDs), compare itemLink
    if type(itemInput) == "string" and (itemInput:find("|Hitem:") or itemInput:find("item:%d+:%d+")) then
        if slotInfo.itemLink then
            -- Normalize item string for comparison
            local inputClean = itemInput:match("(item:[%d:]+)")
            local linkClean = slotInfo.itemLink:match("(item:[%d:]+)")
            if inputClean and linkClean then
                return inputClean == linkClean
            end
        end
    end

    return true
end

--- Queries maximum stack size for an item ID or link.
--- @param itemInput string|number
--- @return number maxStack Maximum stack count (defaults to 100 if unavailable)
function Utils.GetItemMaxStack(itemInput)
    local itemID = Utils.GetItemIdFromString(itemInput)
    if not itemID then return 100 end

    if C_Item and C_Item.GetItemMaxStackSizeByID then
        local maxStack = C_Item.GetItemMaxStackSizeByID(itemID)
        if maxStack and maxStack > 0 then return maxStack end
    end

    ---@diagnostic disable-next-line: deprecated
    local getItemInfo = _G["GetItemInfo"]
    if getItemInfo then
        ---@diagnostic disable-next-line: deprecated
        local _, _, _, _, _, _, _, maxStack = getItemInfo(itemID)
        if maxStack and maxStack > 0 then return maxStack end
    end

    return 100
end

--- Determines whether an item's family is compatible with a bag's specialty family bitmask.
--- @param itemFamily number Item family bitmask from GetItemFamily
--- @param bagFamily number Bag specialty family bitmask from GetBagItemFamily
--- @return boolean compatible True if bag can accept the item
function Utils.IsFamilyCompatible(itemFamily, bagFamily)
    bagFamily = bagFamily or 0
    itemFamily = itemFamily or 0

    -- General bags (family == 0) accept any non-specialty item
    if bagFamily == 0 then
        return true
    end

    -- Specialty bags accept items whose bitmask overlaps with bag family
    if itemFamily == 0 then
        return false
    end

    if bit and bit.band then
        return bit.band(itemFamily, bagFamily) ~= 0
    else
        -- Fallback for environments without bit library: exact match or modulo check
        return itemFamily == bagFamily
    end
end

--- Logs a debug message if debugging is enabled.
--- @param fmt string
--- @param ... any
function Private.DebugLog(fmt, ...)
    local LibStub = _G.LibStub
    local lib = LibStub and LibStub:GetLibrary("LibItemMove-1.0", true)
    if lib and lib.Debug then
        local msg = "[LibItemMove] " .. string.format(tostring(fmt), ...)
        if _G.DEFAULT_CHAT_FRAME then
            _G.DEFAULT_CHAT_FRAME:AddMessage(msg)
        else
            print(msg)
        end
    end
end

return Utils
