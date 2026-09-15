---@type string, LibItemMovePrivate
local ADDON_NAME, Private = ...
Private = Private or {}
local BaseContext = Private.BaseContext
local Utils = Private.Utils
local APIAdapter = Private.APIAdapter

---@class WarbankToBag : BaseContext
local WarbankToBag = BaseContext:New({
    isGuildBank = false,
    isWarbank = true
}) --[[@as WarbankToBag]]
Private.WarbankToBag = WarbankToBag

WarbankToBag.WARBANK_CONTAINERS = { 12, 13, 14, 15, 16 }

--- Returns list of player bag IDs dynamically based on WoW client version.
--- @return number[]
function WarbankToBag:GetPlayerBags()
    return APIAdapter.GetPlayerBagIDs()
end

--- Returns list of active Warbank container IDs.
--- @return number[]
function WarbankToBag:GetWarbankContainers()
    if C_Bank and C_Bank.FetchPurchasedBankTabIDs then
        local bankTypeAccount = (Enum and Enum.BankType and Enum.BankType.Account) or 2
        local tabs = C_Bank.FetchPurchasedBankTabIDs(bankTypeAccount)
        if tabs and #tabs > 0 then
            return tabs
        end
    end
    return self.WARBANK_CONTAINERS
end

--- Checks if player can access the Account Warbank.
--- @return boolean
function WarbankToBag:HasPermission()
    if C_Bank and C_Bank.CanUseBank then
        local bankTypeAccount = (Enum and Enum.BankType and Enum.BankType.Account) or 2
        return C_Bank.CanUseBank(bankTypeAccount)
    end
    return true
end

--- Splits item from Warbank slot and picks up on target bag slot.
--- @param fromSlotId SlotId Packed source slot ID
--- @param toSlotId SlotId Packed target slot ID
--- @param quantity number Quantity to move
function WarbankToBag:MoveSlot(fromSlotId, toSlotId, quantity)
    local sBag, sSlot = Utils.decode_bagslot(fromSlotId)
    local tBag, tSlot = Utils.decode_bagslot(toSlotId)
    APIAdapter.SplitContainerItem(sBag, sSlot, quantity)
    APIAdapter.PickupContainerItem(tBag, tSlot)
end

--- Drops item from cursor onto container slot or picks up slot item.
--- @param bag number Container ID
--- @param slot number Slot index
function WarbankToBag:PickupItem(bag, slot)
    APIAdapter.PickupContainerItem(bag, slot)
end

--- Returns current stack quantity at target slot ID.
--- @param slotId SlotId
--- @return number quantity Stack count (0 if empty)
function WarbankToBag:GetSlotQuantity(slotId)
    local bag, slot = Utils.decode_bagslot(slotId)
    local info = APIAdapter.GetContainerItemInfo(bag, slot)
    return info and info.stackCount or 0
end

--- Returns numeric Item ID at bag and slot.
--- @param bag number
--- @param slot number
--- @return number? itemID
function WarbankToBag:GetSlotItemId(bag, slot)
    return APIAdapter.GetContainerItemID(bag, slot)
end

--- Retrieves list of empty slot IDs in destination player bags sorted by family.
--- @param emptySlotIdsTable SlotId[] Array to populate
function WarbankToBag:GetEmptySlots(emptySlotIdsTable)
    self:ScanEmptySlots(self:GetPlayerBags(), emptySlotIdsTable)
end

--- Retrieves list of partial stack slots in destination player bags.
--- @param itemString string|number
--- @param partialSlotsTable table[]
function WarbankToBag:GetPartialSlots(itemString, partialSlotsTable)
    self:ScanPartialSlots(self:GetPlayerBags(), itemString, partialSlotsTable)
end

--- Iterates Warbank slots containing specified item.
--- @param itemString string|number
--- @return fun(): number?, SlotId?, number?
function WarbankToBag:SlotIterator(itemString)
    return self:ScanSourceSlots(self:GetWarbankContainers(), itemString)
end

WarbankToBag.SlotIdIterator = WarbankToBag.SlotIterator

return WarbankToBag
