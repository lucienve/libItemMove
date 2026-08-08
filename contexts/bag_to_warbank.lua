---@type string, LibItemMovePrivate
local ADDON_NAME, Private = ...
Private = Private or {}
local BaseContext = Private.BaseContext
local Utils = Private.Utils
local APIAdapter = Private.APIAdapter

---@class BagToWarbank : BaseContext
local BagToWarbank = BaseContext:New({
    isGuildBank = false,
    isWarbank = true
}) --[[@as BagToWarbank]]
Private.BagToWarbank = BagToWarbank

BagToWarbank.WARBANK_CONTAINERS = { 13, 14, 15, 16, 17 }

--- Returns list of player bag IDs dynamically based on WoW client version.
--- @return number[]
function BagToWarbank:GetPlayerBags()
    return APIAdapter.GetPlayerBagIDs()
end

--- Splits item from player bag slot and picks up on target Warbank slot.
--- @param fromSlotId SlotId Packed source slot ID
--- @param toSlotId SlotId Packed target slot ID
--- @param quantity number Quantity to move
function BagToWarbank:MoveSlot(fromSlotId, toSlotId, quantity)
    local sBag, sSlot = Utils.decode_bagslot(fromSlotId)
    local tBag, tSlot = Utils.decode_bagslot(toSlotId)
    APIAdapter.SplitContainerItem(sBag, sSlot, quantity)
    APIAdapter.PickupContainerItem(tBag, tSlot)
end

--- Drops item from cursor onto container slot or picks up slot item.
--- @param bag number Container ID
--- @param slot number Slot index
function BagToWarbank:PickupItem(bag, slot)
    APIAdapter.PickupContainerItem(bag, slot)
end

--- Returns current stack quantity at target slot ID.
--- @param slotId SlotId
--- @return number quantity Stack count (0 if empty)
function BagToWarbank:GetSlotQuantity(slotId)
    local bag, slot = Utils.decode_bagslot(slotId)
    local info = APIAdapter.GetContainerItemInfo(bag, slot)
    return info and info.stackCount or 0
end

--- Returns numeric Item ID at bag and slot.
--- @param bag number
--- @param slot number
--- @return number? itemID
function BagToWarbank:GetSlotItemId(bag, slot)
    return APIAdapter.GetContainerItemID(bag, slot)
end

--- Retrieves list of empty slot IDs in destination Warbank tabs sorted by family.
--- @param emptySlotIdsTable SlotId[] Array to populate
function BagToWarbank:GetEmptySlots(emptySlotIdsTable)
    self:ScanEmptySlots(self.WARBANK_CONTAINERS, emptySlotIdsTable)
end

--- Retrieves list of partial stack slots in destination Warbank tabs.
--- @param itemString string|number
--- @param partialSlotsTable table[]
function BagToWarbank:GetPartialSlots(itemString, partialSlotsTable)
    self:ScanPartialSlots(self.WARBANK_CONTAINERS, itemString, partialSlotsTable)
end

--- Iterates player bag slots containing specified item.
--- @param itemString string|number
--- @return fun(): number?, SlotId?, number?
function BagToWarbank:SlotIterator(itemString)
    return self:ScanSourceSlots(self:GetPlayerBags(), itemString)
end

BagToWarbank.SlotIdIterator = BagToWarbank.SlotIterator

return BagToWarbank
