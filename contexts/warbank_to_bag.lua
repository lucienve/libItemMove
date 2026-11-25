---@type string, LibItemMovePrivate
local _, Private = ...
Private = Private or {}
local BaseContext = Private.BaseContext
local Utils = Private.Utils
local APIAdapter = Private.APIAdapter

---@class WarbankToBag : BaseContext
local WarbankToBag = BaseContext:New({
    isGuildBank = false
}) --[[@as WarbankToBag]]
Private.WarbankToBag = WarbankToBag

--- Returns list of player bag IDs dynamically based on WoW client version.
--- @return number[]
function WarbankToBag:GetPlayerBags()
    return APIAdapter.GetPlayerBagIDs()
end

--- Returns list of active Warbank container IDs.
--- @return number[]
function WarbankToBag:GetWarbankContainers()
    return APIAdapter.GetWarbankContainerIDs()
end

--- Checks if player can access the Account Warbank (returns false when C_Bank.CanUseBank is unavailable).
--- @return boolean
function WarbankToBag:HasPermission()
    if C_Bank and C_Bank.CanUseBank then
        local bankTypeAccount = (Enum and Enum.BankType and Enum.BankType.Account) or 2
        return not not C_Bank.CanUseBank(bankTypeAccount)
    end
    return false
end

--- Moves item from Warbank slot to target bag slot, splitting partial stacks and picking up full stacks.
--- @param fromSlotId SlotId Packed source slot ID
--- @param toSlotId SlotId Packed target slot ID
--- @param quantity number Quantity to move
function WarbankToBag:MoveSlot(fromSlotId, toSlotId, quantity)
    if not quantity or quantity <= 0 then
        return
    end
    local currentQty = self:GetSourceSlotQuantity(fromSlotId)
    if currentQty <= 0 then
        return
    end
    local sBag, sSlot = Utils.decode_bagslot(fromSlotId)
    local tBag, tSlot = Utils.decode_bagslot(toSlotId)
    if currentQty > 1 and quantity < currentQty then
        APIAdapter.SplitContainerItem(sBag, sSlot, quantity)
    else
        APIAdapter.PickupContainerItem(sBag, sSlot)
    end
    APIAdapter.PickupContainerItem(tBag, tSlot)
end

--- Drops item from cursor onto container slot or picks up slot item.
--- @param bag number Container ID
--- @param slot number Slot index
function WarbankToBag:PickupItem(bag, slot)
    APIAdapter.PickupContainerItem(bag, slot)
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
