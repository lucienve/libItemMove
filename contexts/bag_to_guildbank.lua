---@type string, LibItemMovePrivate
local _, Private = ...
Private = Private or {}
local BaseContext = Private.BaseContext
local Utils = Private.Utils
local APIAdapter = Private.APIAdapter

local MAX_GUILDBANK_SLOTS_PER_TAB = 98

---@class BagToGuildBank : BaseContext
local BagToGuildBank = BaseContext:New({
    isGuildBank = true
}) --[[@as BagToGuildBank]]
Private.BagToGuildBank = BagToGuildBank

--- Returns list of player bag IDs dynamically based on WoW client version.
--- @return number[]
function BagToGuildBank:GetPlayerBags()
    return APIAdapter.GetPlayerBagIDs()
end

--- Checks if the player has deposit permissions on the current Guild Bank tab.
--- @return boolean hasPermission
function BagToGuildBank:HasPermission()
    if C_GuildBank and C_GuildBank.IsGuildBankEnabled and not C_GuildBank.IsGuildBankEnabled() then
        return false
    end
    local currentTab = (_G.GetCurrentGuildBankTab and _G.GetCurrentGuildBankTab()) or 1
    if _G.GetGuildBankTabInfo then
        local _, _, isViewable, canDeposit = _G.GetGuildBankTabInfo(currentTab)
        if isViewable ~= nil and not canDeposit then
            return false
        end
    end
    return true
end

--- Guild Bank tabs do not support specialty bag families; always returns 0.
--- @param bag number Tab index
--- @return number family 0
function BagToGuildBank:GetBagFamily(bag)
    return 0
end

--- Moves item from player bag slot to target Guild Bank tab slot, splitting partial stacks and picking up full stacks.
--- @param fromSlotId SlotId Packed source slot ID
--- @param toSlotId SlotId Packed target slot ID
--- @param quantity number Quantity to move
function BagToGuildBank:MoveSlot(fromSlotId, toSlotId, quantity)
    if not quantity or quantity <= 0 then
        return
    end
    local currentQty = self:GetSourceSlotQuantity(fromSlotId)
    if currentQty <= 0 then
        return
    end
    local sBag, sSlot = Utils.decode_bagslot(fromSlotId)
    local tTab, tSlot = Utils.decode_bagslot(toSlotId)
    if currentQty > 1 and quantity < currentQty then
        APIAdapter.SplitContainerItem(sBag, sSlot, quantity)
    else
        APIAdapter.PickupContainerItem(sBag, sSlot)
    end
    APIAdapter.PickupGuildBankItem(tTab, tSlot)
end

--- Drops item from cursor onto Guild Bank tab slot or picks up item from tab slot.
--- @param tab number Guild bank tab index
--- @param slot number Slot index
function BagToGuildBank:PickupItem(tab, slot)
    APIAdapter.PickupGuildBankItem(tab, slot)
end

--- Returns current stack quantity at Guild Bank target tab slot ID.
--- @param slotId SlotId
--- @return number count
function BagToGuildBank:GetTargetSlotQuantity(slotId)
    local tab, slot = Utils.decode_bagslot(slotId)
    if _G.GetGuildBankItemInfo then
        local _, count = _G.GetGuildBankItemInfo(tab, slot)
        return count or 0
    end
    return 0
end

--- Returns numeric Item ID at Guild Bank target tab & slot.
--- @param tab number
--- @param slot number
--- @return number? itemID
function BagToGuildBank:GetTargetSlotItemId(tab, slot)
    if _G.GetGuildBankItemLink then
        local link = _G.GetGuildBankItemLink(tab, slot)
        return Utils.GetItemIdFromString(link)
    end
    return nil
end

--- Checks if target Guild Bank tab slot is locked in transit.
--- @param tab number
--- @param slot number
--- @return boolean isLocked
function BagToGuildBank:IsTargetSlotLocked(tab, slot)
    if _G.GetGuildBankItemInfo then
        local _, _, locked = _G.GetGuildBankItemInfo(tab, slot)
        return not not locked
    end
    return false
end

--- Retrieves list of empty slot IDs in current Guild Bank tab.
--- @param emptySlotIdsTable SlotId[] Array to populate
function BagToGuildBank:GetEmptySlots(emptySlotIdsTable)
    local currentTab = (_G.GetCurrentGuildBankTab and _G.GetCurrentGuildBankTab()) or 1

    for slot = 1, MAX_GUILDBANK_SLOTS_PER_TAB do
        local count = self:GetTargetSlotQuantity(Utils.encode_bagslot(currentTab, slot))
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

    for slot = 1, MAX_GUILDBANK_SLOTS_PER_TAB do
        local link = _G.GetGuildBankItemLink and _G.GetGuildBankItemLink(currentTab, slot)
        if link then
            local slotInfo = { itemID = Utils.GetItemIdFromString(link), itemLink = link }
            if Utils.IsItemMatching(itemString, slotInfo) then
                local count = self:GetTargetSlotQuantity(Utils.encode_bagslot(currentTab, slot))
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
        local numSlots = APIAdapter.GetContainerNumSlots(bag)

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
