---@type string, LibItemMovePrivate
local ADDON_NAME, Private = ...
Private = Private or {}
local BaseContext = Private.BaseContext
local Utils = Private.Utils
local APIAdapter = Private.APIAdapter

---@class GuildBankToBag : BaseContext
local GuildBankToBag = BaseContext:New({
    isGuildBank = true,
    isWarbank = false
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
    local currentTab = (_G.GetCurrentGuildBankTab and _G.GetCurrentGuildBankTab()) or 1
    if _G.GetGuildBankTabInfo then
        local name, icon, isViewable, canDeposit, numWithdrawals, remainingWithdrawals = _G.GetGuildBankTabInfo(currentTab)
        if isViewable ~= nil then
            local canWithdraw = (numWithdrawals and numWithdrawals > 0) or (remainingWithdrawals and (remainingWithdrawals > 0 or remainingWithdrawals == -1))
            if not canWithdraw then
                return false
            end
        end
    end
    return true
end

--- Splits item from Guild Bank tab slot and picks up on target bag slot.
--- @param fromSlotId SlotId Packed source slot ID
--- @param toSlotId SlotId Packed target slot ID
--- @param quantity number Quantity to move
function GuildBankToBag:MoveSlot(fromSlotId, toSlotId, quantity)
    local sTab, sSlot = Utils.decode_bagslot(fromSlotId)
    local tBag, tSlot = Utils.decode_bagslot(toSlotId)
    APIAdapter.SplitGuildBankItem(sTab, sSlot, quantity)
    APIAdapter.PickupContainerItem(tBag, tSlot)
end

--- Drops item from cursor onto container slot or picks up slot item.
--- @param bag number Container ID
--- @param slot number Slot index
function GuildBankToBag:PickupItem(bag, slot)
    APIAdapter.PickupContainerItem(bag, slot)
end

--- Returns current stack quantity at target bag slot ID.
--- @param slotId SlotId
--- @return number quantity Stack count (0 if empty)
function GuildBankToBag:GetSlotQuantity(slotId)
    local bag, slot = Utils.decode_bagslot(slotId)
    local info = APIAdapter.GetContainerItemInfo(bag, slot)
    return info and info.stackCount or 0
end

--- Returns numeric Item ID at bag and slot.
--- @param bag number
--- @param slot number
--- @return number? itemID
function GuildBankToBag:GetSlotItemId(bag, slot)
    return APIAdapter.GetContainerItemID(bag, slot)
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

GuildBankToBag.SlotIdIterator = GuildBankToBag.SlotIterator

return GuildBankToBag
