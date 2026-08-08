---@type string, LibItemMovePrivate
local ADDON_NAME, Private = ...
Private = Private or {}
local APIAdapter = {}
Private.APIAdapter = APIAdapter

--- Returns list of player character bag container IDs dynamically based on WoW version.
--- Classic Era (1.15.x): Bag 0 (Backpack) + Bags 1..4 = { 0, 1, 2, 3, 4 }
--- Modern Retail (11.x): Bag 0 + Bags 1..4 + Bag 5 (Reagent Bag) = { 0, 1, 2, 3, 4, 5 }
--- @return number[] playerBags
function APIAdapter.GetPlayerBagIDs()
    local numBagSlots = _G["NUM_BAG_SLOTS"] or 4
    local bags = { 0 }
    for i = 1, numBagSlots do
        table.insert(bags, i)
    end
    -- Check if Reagent Bag (Bag 5) is available in Retail (where NUM_BAG_SLOTS > 4 or REAGENTBAG_CONTAINER exists)
    if _G["REAGENTBAG_CONTAINER"] and _G["REAGENTBAG_CONTAINER"] == 5 then
        table.insert(bags, 5)
    end
    return bags
end

--- Returns list of character bank container IDs dynamically based on WoW version.
--- Classic Era: -1 (BANK_CONTAINER) + Bank Bags 5..11
--- Modern Retail: -1 (BANK_CONTAINER) + -3 (REAGENTBANK_CONTAINER) + Bank Bags 6..12
--- @return number[] bankContainers
function APIAdapter.GetBankContainerIDs()
    local containers = { -1 }

    -- Reagent Bank (-3) in Retail / modern expansions
    local isUnlockedFn = _G["IsReagentBankUnlocked"]
    if _G["REAGENTBANK_CONTAINER"] or (type(isUnlockedFn) == "function" and isUnlockedFn()) then
        table.insert(containers, -3)
    end

    local numBagSlots = _G["NUM_BAG_SLOTS"] or 4
    local numBankSlots = _G["NUM_BANKBAGSLOTS"] or 7
    local startBankBag = numBagSlots + 1 -- Bag 5 in Classic (NUM_BAG_SLOTS=4), Bag 6 in Retail (NUM_BAG_SLOTS=5)

    for i = startBankBag, startBankBag + numBankSlots - 1 do
        table.insert(containers, i)
    end

    return containers
end

--- Returns normalized container item information table or nil if slot is empty.
--- Safe against single-table returns (C_Container) vs multi-returns (Classic Era).
--- @param bag number Container ID
--- @param slot number Slot index
--- @return table? info Table with fields: stackCount, isLocked, itemID, isBound, itemLink
function APIAdapter.GetContainerItemInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if type(info) == "table" then
            ---@cast info table
            return {
                stackCount = info.stackCount or 0,
                isLocked = info.isLocked or false,
                itemID = info.itemID,
                isBound = info.isBound or false,
                itemLink = info.hyperLink or info.itemLink
            }
        end
    end

    -- Fallback for Classic Era GetContainerItemInfo
    local legacyGetInfo = _G["GetContainerItemInfo"]
    if legacyGetInfo then
        local ret1, count, locked, quality, readable, lootable, link, isFiltered, noValue, itemID, isBound = legacyGetInfo(bag, slot)

        -- Safeguard: If GetContainerItemInfo returned a single table (e.g. redirected by another addon or wrapper)
        if type(ret1) == "table" then
            return {
                stackCount = ret1.stackCount or 0,
                isLocked = ret1.isLocked or false,
                itemID = ret1.itemID,
                isBound = ret1.isBound or false,
                itemLink = ret1.hyperLink or ret1.itemLink
            }
        elseif ret1 or count or itemID then
            return {
                stackCount = count or 0,
                isLocked = locked or false,
                itemID = itemID,
                isBound = isBound or false,
                itemLink = link
            }
        end
    end

    return nil
end

--- Returns numeric item ID at bag and slot.
--- @param bag number Container ID
--- @param slot number Slot index
--- @return number? itemID Item ID if slot contains an item
function APIAdapter.GetContainerItemID(bag, slot)
    if C_Container and C_Container.GetContainerItemID then
        return C_Container.GetContainerItemID(bag, slot)
    end
    local getItemID = _G["GetContainerItemID"]
    if getItemID then
        return getItemID(bag, slot)
    end
    local info = APIAdapter.GetContainerItemInfo(bag, slot)
    return info and info.itemID
end

--- Splits quantity from bag slot onto cursor.
--- @param bag number Container ID
--- @param slot number Slot index
--- @param count number Quantity to split onto cursor
function APIAdapter.SplitContainerItem(bag, slot, count)
    if C_Container and C_Container.SplitContainerItem then
        C_Container.SplitContainerItem(bag, slot, count)
    else
        local split = _G["SplitContainerItem"]
        if split then
            split(bag, slot, count)
        end
    end
end

--- Swaps item on cursor with bag slot or picks up slot item.
--- @param bag number Container ID
--- @param slot number Slot index
function APIAdapter.PickupContainerItem(bag, slot)
    if C_Container and C_Container.PickupContainerItem then
        C_Container.PickupContainerItem(bag, slot)
    else
        local pickup = _G["PickupContainerItem"]
        if pickup then
            pickup(bag, slot)
        end
    end
end

--- Splits items from Guild Bank tab slot onto cursor.
--- @param tab number Guild bank tab index
--- @param slot number Slot index within tab
--- @param count number Quantity to split onto cursor
function APIAdapter.SplitGuildBankItem(tab, slot, count)
    local splitGB = _G["SplitGuildBankItem"]
    if splitGB then
        splitGB(tab, slot, count)
    end
end

--- Drops cursor item onto Guild Bank tab slot or picks up item from tab slot.
--- @param tab number Guild bank tab index
--- @param slot number Slot index within tab
function APIAdapter.PickupGuildBankItem(tab, slot)
    local pickupGB = _G["PickupGuildBankItem"]
    if pickupGB then
        pickupGB(tab, slot)
    end
end

--- Returns cursor payload type and extra info (e.g. "item", itemID).
--- @return string? cursorType "item" | "money" | "spell" | nil
--- @return any info1 Primary cursor info (e.g. item ID)
--- @return any info2 Secondary cursor info
function APIAdapter.GetCursorInfo()
    local getCursor = _G["GetCursorInfo"]
    if getCursor then
        return getCursor()
    end
    return nil
end

--- Clears cursor contents, destroying/returning items held on cursor.
function APIAdapter.ClearCursor()
    local clearCursor = _G["ClearCursor"]
    if clearCursor then
        clearCursor()
    end
end

--- Queries specialty item family bitmask for an item link or ID.
--- @param itemInput string|number Item ID or item link
--- @return number family Bitmask integer (0 for general items)
function APIAdapter.GetItemFamily(itemInput)
    if not itemInput then return 0 end
    if C_Item and C_Item.GetItemFamily then
        local family = C_Item.GetItemFamily(itemInput)
        if family then return family end
    end
    -- Fallback for legacy Classic client API where GetItemFamily is global
    ---@diagnostic disable-next-line: deprecated
    local legacyGetFamily = _G["GetItemFamily"]
    if legacyGetFamily then
        ---@diagnostic disable-next-line: deprecated
        local family = legacyGetFamily(itemInput)
        if family then return family end
    end
    return 0
end

--- Returns specialty bag family bitmask for a container ID.
--- @param bag number Container ID
--- @return number family Specialty family bitmask (0 for general bags)
function APIAdapter.GetBagItemFamily(bag)
    if not bag or bag <= 0 then return 0 end

    local invID = nil
    if C_Container and C_Container.ContainerIDToInventoryID then
        invID = C_Container.ContainerIDToInventoryID(bag)
    else
        local getInvID = _G["ContainerIDToInventoryID"]
        if getInvID then
            invID = getInvID(bag)
        end
    end

    local getInvLink = _G["GetInventoryItemLink"]
    if invID and getInvLink then
        local bagLink = getInvLink("player", invID)
        if bagLink then
            return APIAdapter.GetItemFamily(bagLink)
        end
    end
    return 0
end

return APIAdapter
