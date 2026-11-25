---@type string, LibItemMovePrivate
local _, Private = ...
Private = Private or {}
local BaseContext = Private.BaseContext
local Utils = Private.Utils
local APIAdapter = Private.APIAdapter

---@class GuildBankToBag : BaseContext
local GuildBankToBag = BaseContext:New({
    isGuildBank = true
}) --[[@as GuildBankToBag]]
Private.GuildBankToBag = GuildBankToBag

--- Returns list of player bag IDs dynamically based on WoW client version.
--- @return number[]
function GuildBankToBag:GetPlayerBags()
    return APIAdapter.GetPlayerBagIDs()
end

--- Checks if the player has withdrawal permissions on the current Guild Bank tab.
--- @return boolean hasPermission
function GuildBankToBag:HasPermission()
    if C_GuildBank and C_GuildBank.IsGuildBankEnabled and not C_GuildBank.IsGuildBankEnabled() then
        return false
    end
    local currentTab = (_G.GetCurrentGuildBankTab and _G.GetCurrentGuildBankTab()) or 1
    if _G.GetGuildBankTabInfo then
        local _, _, isViewable, _, numWithdrawals, remainingWithdrawals = _G.GetGuildBankTabInfo(currentTab)
        if isViewable ~= nil then
            local canWithdraw = (numWithdrawals and numWithdrawals > 0) or (remainingWithdrawals and (remainingWithdrawals > 0 or remainingWithdrawals == -1))
            if not canWithdraw then
                return false
            end
        end
    end
    return true
end

--- Moves item from Guild Bank tab slot to target bag slot, splitting partial stacks and picking up full stacks.
--- @param fromSlotId SlotId Packed source slot ID
--- @param toSlotId SlotId Packed target slot ID
--- @param quantity number Quantity to move
function GuildBankToBag:MoveSlot(fromSlotId, toSlotId, quantity)
    if not quantity or quantity <= 0 then
        return
    end
    local currentQty = self:GetSourceSlotQuantity(fromSlotId)
    if currentQty <= 0 then
        return
    end
    local sTab, sSlot = Utils.decode_bagslot(fromSlotId)
    local tBag, tSlot = Utils.decode_bagslot(toSlotId)
    if currentQty > 1 and quantity < currentQty then
        APIAdapter.SplitGuildBankItem(sTab, sSlot, quantity)
    else
        APIAdapter.PickupGuildBankItem(sTab, sSlot)
    end
    APIAdapter.PickupContainerItem(tBag, tSlot)
end

--- Drops item from cursor onto container slot or picks up slot item.
--- @param bag number Container ID
--- @param slot number Slot index
function GuildBankToBag:PickupItem(bag, slot)
    APIAdapter.PickupContainerItem(bag, slot)
end

--- Returns current item quantity in Guild Bank source tab slot ID.
--- @param slotId SlotId
--- @return number count
function GuildBankToBag:GetSourceSlotQuantity(slotId)
    local tab, slot = Utils.decode_bagslot(slotId)
    if _G.GetGuildBankItemInfo then
        local _, count = _G.GetGuildBankItemInfo(tab, slot)
        return count or 0
    end
    return 0
end

--- Checks if source Guild Bank tab slot is locked in transit.
--- @param tab number
--- @param slot number
--- @return boolean isLocked
function GuildBankToBag:IsSourceSlotLocked(tab, slot)
    if _G.GetGuildBankItemInfo then
        local _, _, locked = _G.GetGuildBankItemInfo(tab, slot)
        return not not locked
    end
    return false
end

--- Retrieves list of empty slot IDs in destination player bags sorted by family.
--- @param emptySlotIdsTable SlotId[] Array to populate
function GuildBankToBag:GetEmptySlots(emptySlotIdsTable)
    self:ScanEmptySlots(self:GetPlayerBags(), emptySlotIdsTable)
end

--- Retrieves list of partial stack slots in destination player bags.
--- @param itemString string|number
--- @param partialSlotsTable table[]
function GuildBankToBag:GetPartialSlots(itemString, partialSlotsTable)
    self:ScanPartialSlots(self:GetPlayerBags(), itemString, partialSlotsTable)
end

--- Iterates current Guild Bank tab slots containing specified item.
--- @param itemString string|number
--- @return fun(): number?, SlotId?, number?
function GuildBankToBag:SlotIterator(itemString)
    local slotList = {}
    local currentTab = (_G.GetCurrentGuildBankTab and _G.GetCurrentGuildBankTab()) or 1
    local MAX_GUILDBANK_SLOTS_PER_TAB = 98

    for slot = 1, MAX_GUILDBANK_SLOTS_PER_TAB do
        local link = _G.GetGuildBankItemLink and _G.GetGuildBankItemLink(currentTab, slot)
        if link then
            local itemID = Utils.GetItemIdFromString(link)
            local slotInfo = { itemID = itemID, itemLink = link }
            if Utils.IsItemMatching(itemString, slotInfo) then
                local count = 0
                if _G.GetGuildBankItemInfo then
                    local _, c = _G.GetGuildBankItemInfo(currentTab, slot)
                    count = c or 0
                end
                if count > 0 then
                    table.insert(slotList, {
                        slotId = Utils.encode_bagslot(currentTab, slot),
                        qty = count
                    })
                end
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
