---@type string, LibItemMovePrivate
local ADDON_NAME, Private = ...
Private = Private or {}
local BaseContext = Private.BaseContext
local Utils = Private.Utils
local APIAdapter = Private.APIAdapter

---@class BankToBag : BaseContext
local BankToBag = BaseContext:New({
    isGuildBank = false,
    isWarbank = false
}) --[[@as BankToBag]]
Private.BankToBag = BankToBag

BankToBag.PLAYER_BAGS = { 0, 1, 2, 3, 4, 5 }
BankToBag.BANK_CONTAINERS = { -1, 6, 7, 8, 9, 10, 11, 12 }

--- Splits item from bank slot and picks up on target bag slot.
--- @param fromSlotId SlotId Packed source slot ID
--- @param toSlotId SlotId Packed target slot ID
--- @param quantity number Quantity to move
function BankToBag:MoveSlot(fromSlotId, toSlotId, quantity)
    local sBag, sSlot = Utils.decode_bagslot(fromSlotId)
    local tBag, tSlot = Utils.decode_bagslot(toSlotId)
    APIAdapter.SplitContainerItem(sBag, sSlot, quantity)
    APIAdapter.PickupContainerItem(tBag, tSlot)
end

--- Drops item from cursor onto container slot or picks up slot item.
--- @param bag number Container ID
--- @param slot number Slot index
function BankToBag:PickupItem(bag, slot)
    APIAdapter.PickupContainerItem(bag, slot)
end

--- Returns current stack quantity at target slot ID.
--- @param slotId SlotId
--- @return number quantity Stack count (0 if empty)
function BankToBag:GetSlotQuantity(slotId)
    local bag, slot = Utils.decode_bagslot(slotId)
    local info = APIAdapter.GetContainerItemInfo(bag, slot)
    return info and info.stackCount or 0
end

--- Returns numeric Item ID at bag and slot.
--- @param bag number
--- @param slot number
--- @return number? itemID
function BankToBag:GetSlotItemId(bag, slot)
    return APIAdapter.GetContainerItemID(bag, slot)
end

--- Retrieves list of empty slot IDs in destination player bags sorted by family.
--- @param emptySlotIdsTable SlotId[] Array to populate
function BankToBag:GetEmptySlots(emptySlotIdsTable)
    self:ScanEmptySlots(self.PLAYER_BAGS, emptySlotIdsTable)
end

--- Retrieves list of partial stack slots in destination player bags.
--- @param itemString string|number
--- @param partialSlotsTable table[]
function BankToBag:GetPartialSlots(itemString, partialSlotsTable)
    self:ScanPartialSlots(self.PLAYER_BAGS, itemString, partialSlotsTable)
end

--- Iterates bank slots containing specified item.
--- @param itemString string|number
--- @return fun(): number?, SlotId?, number?
function BankToBag:SlotIterator(itemString)
    return self:ScanSourceSlots(self.BANK_CONTAINERS, itemString)
end

BankToBag.SlotIdIterator = BankToBag.SlotIterator

return BankToBag
