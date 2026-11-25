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

--- Returns list of bank container IDs dynamically based on WoW client version (-1, optional -3, 5..11 in Classic; 6..11 in Retail; 6..14 in WoW Forever).
--- @return number[]
function BagToBank:GetBankContainers()
    return APIAdapter.GetBankContainerIDs()
end

--- Checks if player can access the Character Bank.
--- Falls back to true on legacy clients where C_Bank is unavailable.
--- @return boolean
function BagToBank:HasPermission()
    if C_Bank and C_Bank.CanUseBank then
        local bankTypeCharacter = (Enum and Enum.BankType and Enum.BankType.Character) or 0
        return not not C_Bank.CanUseBank(bankTypeCharacter)
    end
    return true
end

--- Moves item from source bag slot to target bank slot, splitting partial stacks and picking up full stacks.
--- @param fromSlotId SlotId Packed source slot ID
--- @param toSlotId SlotId Packed target slot ID
--- @param quantity number Quantity to move
function BagToBank:MoveSlot(fromSlotId, toSlotId, quantity)
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
function BagToBank:PickupItem(bag, slot)
    APIAdapter.PickupContainerItem(bag, slot)
end

--- Returns current stack quantity at slot ID.
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

local function IsAllowedInCharacterBank(bag, slot)
    local bankTypeCharacter = (Enum and Enum.BankType and Enum.BankType.Character) or 0
    return APIAdapter.IsItemAllowedInBankType(bankTypeCharacter, bag, slot)
end

--- Iterates player bag slots containing specified item allowed in Character Bank via C_Bank.IsItemAllowedInBankType.
--- @param itemString string|number
--- @return fun(): number?, SlotId?, number?
function BagToBank:SlotIterator(itemString)
    return self:ScanSourceSlots(self:GetPlayerBags(), itemString, IsAllowedInCharacterBank)
end

BagToBank.SlotIdIterator = BagToBank.SlotIterator

return BagToBank
