---@type string, LibItemMovePrivate
local ADDON_NAME, Private = ...
Private = Private or {}
local BaseContext = Private.BaseContext
local Utils = Private.Utils
local APIAdapter = Private.APIAdapter

---@class BagToGuildBank : BaseContext
local BagToGuildBank = BaseContext:New({
    isGuildBank = true,
    isWarbank = false
}) --[[@as BagToGuildBank]]
Private.BagToGuildBank = BagToGuildBank

--- Returns list of player bag IDs dynamically based on WoW client version.
--- @return number[]
function BagToGuildBank:GetPlayerBags()
    return APIAdapter.GetPlayerBagIDs()
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

--- Checks if the player has deposit permissions on the current Guild Bank tab.
--- @return boolean hasPermission
function BagToGuildBank:HasPermission()
    local currentTab = (_G.GetCurrentGuildBankTab and _G.GetCurrentGuildBankTab()) or 1
    if _G.GetGuildBankTabInfo then
        local name, icon, isViewable, canDeposit, numWithdrawals, remainingWithdrawals = _G.GetGuildBankTabInfo(currentTab)
        if isViewable ~= nil and not canDeposit then
            return false
        end
    end
    return true
end

--- Splits item from player bag slot and picks up on target Guild Bank tab slot.
--- @param fromSlotId SlotId Packed source slot ID
--- @param toSlotId SlotId Packed target slot ID
--- @param quantity number Quantity to move
function BagToGuildBank:MoveSlot(fromSlotId, toSlotId, quantity)
    local sBag, sSlot = Utils.decode_bagslot(fromSlotId)
    local tTab, tSlot = Utils.decode_bagslot(toSlotId)
    APIAdapter.SplitContainerItem(sBag, sSlot, quantity)
    APIAdapter.PickupGuildBankItem(tTab, tSlot)
end

--- Drops item from cursor onto Guild Bank tab slot or picks up item from tab slot.
--- @param tab number Guild bank tab index
--- @param slot number Slot index
function BagToGuildBank:PickupItem(tab, slot)
    APIAdapter.PickupGuildBankItem(tab, slot)
end

--- Returns current item quantity in target Guild Bank tab slot ID.
--- @param slotId SlotId
--- @return number count
function BagToGuildBank:GetSlotQuantity(slotId)
    local tab, slot = Utils.decode_bagslot(slotId)

    if _G.GetGuildBankItemInfo then
        local _, count = _G.GetGuildBankItemInfo(tab, slot)
        return count or 0
    end
    return 0
end

--- Returns numeric Item ID in target Guild Bank tab slot.
--- @param tab number Guild bank tab index
--- @param slot number Slot index
--- @return number? itemID
function BagToGuildBank:GetSlotItemId(tab, slot)
    if _G.GetGuildBankItemLink then
        local link = _G.GetGuildBankItemLink(tab, slot)
        return Utils.GetItemIdFromString(link)
    end
    return nil
end

--- Retrieves list of empty slot IDs in current Guild Bank tab.
--- @param emptySlotIdsTable SlotId[] Array to populate
function BagToGuildBank:GetEmptySlots(emptySlotIdsTable)
    local currentTab = (_G.GetCurrentGuildBankTab and _G.GetCurrentGuildBankTab()) or 1
    local MAX_GUILDBANK_SLOTS_PER_TAB = 98

    for slot = 1, MAX_GUILDBANK_SLOTS_PER_TAB do
        local count = self:GetSlotQuantity(Utils.encode_bagslot(currentTab, slot))
        if count == 0 then
            table.insert(emptySlotIdsTable, Utils.encode_bagslot(currentTab, slot))
        end
    end
end

--- Retrieves list of partial stack slots in current Guild Bank tab.
--- @param itemString string|number
--- @param partialSlotsTable table[]
function BagToGuildBank:GetPartialSlots(itemString, partialSlotsTable)
    local itemID = Utils.GetItemIdFromString(itemString)
    if not itemID then return end
    local maxStack = Utils.GetItemMaxStack(itemID)
    if maxStack <= 1 then return end

    local currentTab = (_G.GetCurrentGuildBankTab and _G.GetCurrentGuildBankTab()) or 1
    local MAX_GUILDBANK_SLOTS_PER_TAB = 98

    for slot = 1, MAX_GUILDBANK_SLOTS_PER_TAB do
        local link = _G.GetGuildBankItemLink and _G.GetGuildBankItemLink(currentTab, slot)
        if link then
            local slotInfo = { itemID = Utils.GetItemIdFromString(link), itemLink = link }
            if Utils.IsItemMatching(itemString, slotInfo) then
                local count = self:GetSlotQuantity(Utils.encode_bagslot(currentTab, slot))
                if count > 0 and count < maxStack then
                    table.insert(partialSlotsTable, {
                        slotId = Utils.encode_bagslot(currentTab, slot),
                        currentQty = count,
                        roomLeft = maxStack - count
                    })
                end
            end
        end
    end
end

--- Iterates player bag slots containing non-soulbound instances of specified item.
--- @param itemString string|number
--- @return fun(): number?, SlotId?, number?
function BagToGuildBank:SlotIterator(itemString)
    local slotList = {}

    for _, bag in ipairs(self:GetPlayerBags()) do
        local numSlots = GetContainerNumSlots(bag)

        for slot = 1, numSlots do
            local info = APIAdapter.GetContainerItemInfo(bag, slot)
            -- Soulbound items cannot be moved to Guild Bank
            if info and info.stackCount > 0 and not info.isBound and Utils.IsItemMatching(itemString, info) then
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

BagToGuildBank.SlotIdIterator = BagToGuildBank.SlotIterator

return BagToGuildBank
