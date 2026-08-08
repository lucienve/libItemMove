---@type string, LibItemMovePrivate
local ADDON_NAME, Private = ...
Private = Private or {}
local BaseContext = Private.BaseContext
local Utils = Private.Utils
local APIAdapter = Private.APIAdapter

---@class BagToBank : BaseContext
local BagToBank = BaseContext:New({
    isGuildBank = false,
    isWarbank = false
}) --[[@as BagToBank]]
Private.BagToBank = BagToBank

BagToBank.PLAYER_BAGS = { 0, 1, 2, 3, 4, 5 }
BagToBank.BANK_CONTAINERS = { -1, 6, 7, 8, 9, 10, 11, 12 }

--- Splits item from source slot and picks up on target bank slot.
--- @param fromSlotId SlotId Packed source slot ID
--- @param toSlotId SlotId Packed target slot ID
--- @param quantity number Quantity to move
function BagToBank:MoveSlot(fromSlotId, toSlotId, quantity)
    local sBag, sSlot = Utils.decode_bagslot(fromSlotId)
    local tBag, tSlot = Utils.decode_bagslot(toSlotId)
    APIAdapter.SplitContainerItem(sBag, sSlot, quantity)
    APIAdapter.PickupContainerItem(tBag, tSlot)
end

--- Drops item from cursor onto container slot or picks up slot item.
--- @param bag number Container ID
--- @param slot number Slot index
function BagToBank:PickupItem(bag, slot)
    APIAdapter.PickupContainerItem(bag, slot)
end

--- Returns current stack quantity at target slot ID.
--- @param slotId SlotId
--- @return number quantity Stack count (0 if empty)
function BagToBank:GetSlotQuantity(slotId)
    local bag, slot = Utils.decode_bagslot(slotId)
    local info = APIAdapter.GetContainerItemInfo(bag, slot)
    return info and info.stackCount or 0
end

--- Returns numeric Item ID at bag and slot.
--- @param bag number
--- @param slot number
--- @return number? itemID
function BagToBank:GetSlotItemId(bag, slot)
    return APIAdapter.GetContainerItemID(bag, slot)
end

--- Retrieves list of empty slot IDs in destination bank containers sorted by family.
--- @param emptySlotIdsTable SlotId[] Array to populate
function BagToBank:GetEmptySlots(emptySlotIdsTable)
    self:ScanEmptySlots(self.BANK_CONTAINERS, emptySlotIdsTable)
end

--- Retrieves list of partial stack slots in destination bank containers.
--- @param itemString string|number
--- @param partialSlotsTable table[]
function BagToBank:GetPartialSlots(itemString, partialSlotsTable)
    self:ScanPartialSlots(self.BANK_CONTAINERS, itemString, partialSlotsTable)
end

--- Iterates player bag slots containing specified item.
--- @param itemString string|number
--- @return fun(): number?, SlotId?, number?
function BagToBank:SlotIterator(itemString)
    return self:ScanSourceSlots(self.PLAYER_BAGS, itemString)
end

BagToBank.SlotIdIterator = BagToBank.SlotIterator

return BagToBank
