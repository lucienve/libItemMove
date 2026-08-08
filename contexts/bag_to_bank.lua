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

--- Returns list of player bag IDs dynamically based on WoW client version.
--- @return number[]
function BagToBank:GetPlayerBags()
    return APIAdapter.GetPlayerBagIDs()
end

--- Returns list of bank container IDs dynamically based on WoW client version (-1, -3, 5..11 in Classic or 6..12 in Retail).
--- @return number[]
function BagToBank:GetBankContainers()
    return APIAdapter.GetBankContainerIDs()
end

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
    self:ScanEmptySlots(self:GetBankContainers(), emptySlotIdsTable)
end

--- Retrieves list of partial stack slots in destination bank containers.
--- @param itemString string|number
--- @param partialSlotsTable table[]
function BagToBank:GetPartialSlots(itemString, partialSlotsTable)
    self:ScanPartialSlots(self:GetBankContainers(), itemString, partialSlotsTable)
end

--- Iterates player bag slots containing specified item.
--- @param itemString string|number
--- @return fun(): number?, SlotId?, number?
function BagToBank:SlotIterator(itemString)
    return self:ScanSourceSlots(self:GetPlayerBags(), itemString)
end

BagToBank.SlotIdIterator = BagToBank.SlotIterator

return BagToBank
