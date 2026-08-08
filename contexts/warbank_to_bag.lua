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

WarbankToBag.PLAYER_BAGS = { 0, 1, 2, 3, 4, 5 }
WarbankToBag.WARBANK_CONTAINERS = { 13, 14, 15, 16, 17 }

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
    self:ScanEmptySlots(self.PLAYER_BAGS, emptySlotIdsTable)
end

--- Retrieves list of partial stack slots in destination player bags.
--- @param itemString string|number
--- @param partialSlotsTable table[]
function WarbankToBag:GetPartialSlots(itemString, partialSlotsTable)
    self:ScanPartialSlots(self.PLAYER_BAGS, itemString, partialSlotsTable)
end

--- Iterates Warbank slots containing specified item.
--- @param itemString string|number
--- @return fun(): number?, SlotId?, number?
function WarbankToBag:SlotIterator(itemString)
    return self:ScanSourceSlots(self.WARBANK_CONTAINERS, itemString)
end

WarbankToBag.SlotIdIterator = WarbankToBag.SlotIterator

return WarbankToBag
