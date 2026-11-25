---@type string, LibItemMovePrivate
local ADDON_NAME, Private = ...
Private = Private or {}
local APIAdapter = {}
Private.APIAdapter = APIAdapter

local REAGENT_BAG_FAMILY = (Private.Utils and Private.Utils.REAGENT_BAG_FAMILY) or 2048

--- Returns true if the current WoW client exposes a dedicated player Reagent Bag slot.
--- Classic Era and Mists Classic define Enum.BagIndex.ReagentBag = 5 alongside legacy bank bags at 5,
--- so availability is gated by NUM_REAGENTBAG_SLOTS or REAGENTBAG_CONTAINER == 5 without a legacy bank offset.
--- @return boolean hasReagentBag
local function HasReagentBagSlot()
    local bankBagOffset = _G["ITEM_INVENTORY_BANK_BAG_OFFSET"]
    local hasLegacyBankAt5 = type(bankBagOffset) == "number" and bankBagOffset > 0 and bankBagOffset < 5
    local numReagentBagSlots = _G["NUM_REAGENTBAG_SLOTS"]
        or (_G.Constants and _G.Constants.InventoryConstants and _G.Constants.InventoryConstants.NumReagentBagSlots)
        or 0
    return numReagentBagSlots > 0 or (_G["REAGENTBAG_CONTAINER"] == 5 and not hasLegacyBankAt5)
end

--- Returns the container ID for the player Reagent Bag slot (defaults to 5).
--- @return number reagentBagID
local function GetReagentBagID()
    local bagIndex = Enum and Enum.BagIndex --[[@as table<string, number?>]]
    if type(bagIndex) == "table" and type(bagIndex["ReagentBag"]) == "number" then
        return bagIndex["ReagentBag"]
    end
    local reagentContainer = _G["REAGENTBAG_CONTAINER"]
    if type(reagentContainer) == "number" then
        return reagentContainer
    end
    return 5
end

--- Returns true when bag refers to the player's Reagent Bag slot on clients that support it.
--- @param bag number Container ID
--- @return boolean isReagentBag
local function IsReagentBag(bag)
    if not HasReagentBagSlot() then
        return false
    end
    return bag == GetReagentBagID()
end

--- Returns list of player character bag container IDs dynamically based on WoW version.
--- Classic Era (1.15.x) & Mists of Pandaria Classic (5.5.x): Bag 0 (Backpack) + Bags 1..4 = { 0, 1, 2, 3, 4 }
--- Modern Retail (11.x/12.x) & WoW Forever (1.60.x): Bag 0 + Bags 1..4 + Bag 5 (Reagent Bag) = { 0, 1, 2, 3, 4, 5 }
--- @return number[] playerBags
function APIAdapter.GetPlayerBagIDs()
    local numBagSlots = _G["NUM_BAG_SLOTS"] or 4
    local bags = { 0 }
    for i = 1, numBagSlots do
        table.insert(bags, i)
    end
    if HasReagentBagSlot() then
        table.insert(bags, GetReagentBagID())
    end
    return bags
end

--- Collects contiguous numeric enum values from Enum.BagIndex for a given prefix
--- (e.g., "CharacterBankTab_" or "AccountBankTab_"), starting at index 1.
--- @param prefix string Enum.BagIndex member prefix
--- @return number[] tabIDs
local function CollectEnumBankTabIDs(prefix)
    local tabs = {}
    local bagIndex = Enum and Enum.BagIndex --[[@as table<string, number?>]]
    if type(bagIndex) ~= "table" then
        return tabs
    end
    local i = 1
    while true do
        local bagID = bagIndex[prefix .. i]
        if type(bagID) ~= "number" then
            break
        end
        table.insert(tabs, bagID)
        i = i + 1
    end
    return tabs
end

--- Queries C_Bank.FetchPurchasedBankTabIDs for a bankType when available.
--- Returns a table (including {} for 0 tabs) if the API exists, or nil if C_Bank is unavailable.
--- @param bankType number Enum.BankType value
--- @return number[]? tabIDs
local function FetchPurchasedBankTabs(bankType)
    if C_Bank and C_Bank.FetchPurchasedBankTabIDs then
        local tabs = C_Bank.FetchPurchasedBankTabIDs(bankType)
        if type(tabs) == "table" then
            return tabs
        end
        return {}
    end
    return nil
end

--- Checks whether bag matches any contiguous Enum.BagIndex member for a prefix.
--- @param bagIndex table<string, number?>
--- @param prefix string
--- @param bag number
--- @return boolean
local function IsEnumBankTabPrefix(bagIndex, prefix, bag)
    local i = 1
    while true do
        local tabID = bagIndex[prefix .. i]
        if type(tabID) ~= "number" then
            return false
        end
        if tabID == bag then
            return true
        end
        i = i + 1
    end
end

--- Returns true when bag corresponds to a modern virtual bank or Warbank tab.
--- @param bag number Container ID
--- @return boolean isModernTab
local function IsModernBankTab(bag)
    local bagIndex = Enum and Enum.BagIndex --[[@as table<string, number?>]]
    if type(bagIndex) == "table" and type(bagIndex["CharacterBankTab_1"]) == "number" then
        if IsEnumBankTabPrefix(bagIndex, "CharacterBankTab_", bag) or IsEnumBankTabPrefix(bagIndex, "AccountBankTab_", bag) then
            return true
        end
    end

    if C_Bank and C_Bank.FetchPurchasedBankTabIDs then
        local bankTypeCharacter = (Enum and Enum.BankType and Enum.BankType.Character) or 0
        local charTabs = FetchPurchasedBankTabs(bankTypeCharacter)
        if charTabs then
            for _, tabID in ipairs(charTabs) do
                if tabID == bag then
                    return true
                end
            end
        end

        local bankTypeAccount = (Enum and Enum.BankType and Enum.BankType.Account) or 2
        local accountTabs = FetchPurchasedBankTabs(bankTypeAccount)
        if accountTabs then
            for _, tabID in ipairs(accountTabs) do
                if tabID == bag then
                    return true
                end
            end
        end
    end

    return false
end

--- Returns list of character bank container IDs dynamically based on WoW version.
--- Classic Era / Mists Classic: -1 (BANK_CONTAINER), optional -3 (Reagent Bank), and Bank Bags 5..11
--- Modern Retail (11.2+ / 12.x): CharacterBankTab_1..6 (6..11) via C_Bank or Enum.BagIndex
--- WoW Forever (16001): CharacterBankTab_1..9 (6..14) via C_Bank or Enum.BagIndex
--- @return number[] bankContainers
function APIAdapter.GetBankContainerIDs()
    -- Modern Retail (11.2+ / 12.x) and WoW Forever (16001): trust C_Bank directly (including {} when 0 tabs are purchased)
    local bankTypeCharacter = (Enum and Enum.BankType and Enum.BankType.Character) or 0
    local purchasedTabs = FetchPurchasedBankTabs(bankTypeCharacter)
    if purchasedTabs then
        return purchasedTabs
    end

    local enumTabs = CollectEnumBankTabIDs("CharacterBankTab_")
    if #enumTabs > 0 then
        return enumTabs
    end

    -- Classic / Legacy Bank layout
    local containers = { -1 }

    -- Reagent Bank (-3) in legacy expansions (WoD through Dragonflight / TWW 11.1.x)
    local isUnlockedFn = _G["IsReagentBankUnlocked"]
    if type(isUnlockedFn) == "function" and isUnlockedFn() then
        table.insert(containers, _G["REAGENTBANK_CONTAINER"] or -3)
    end

    local numBagSlots = _G["NUM_BAG_SLOTS"] or 4
    local numBankSlots = _G["NUM_BANKBAGSLOTS"] or (_G.Constants and _G.Constants.InventoryConstants and _G.Constants.InventoryConstants.NumBankBagSlots) or 7
    local bankBagOffset = _G["ITEM_INVENTORY_BANK_BAG_OFFSET"]
    local startBankBag
    if type(bankBagOffset) == "number" and bankBagOffset > 0 then
        startBankBag = bankBagOffset + 1
    else
        startBankBag = numBagSlots + 1
        if HasReagentBagSlot() then
            startBankBag = startBankBag + 1
        end
    end

    for i = startBankBag, startBankBag + numBankSlots - 1 do
        table.insert(containers, i)
    end

    return containers
end

--- Returns list of account (Warbank) container IDs dynamically based on WoW version.
--- Classic Era / Mists Classic: {} (Warbank unsupported)
--- Modern Retail (11.2+ / 12.x): AccountBankTab_1..5 (12..16) via C_Bank or Enum.BagIndex
--- WoW Forever (16001): AccountBankTab_1..9 (15..23) via C_Bank or Enum.BagIndex
--- @return number[] warbankContainers
function APIAdapter.GetWarbankContainerIDs()
    local bankTypeAccount = (Enum and Enum.BankType and Enum.BankType.Account) or 2
    local purchasedTabs = FetchPurchasedBankTabs(bankTypeAccount)
    if purchasedTabs then
        return purchasedTabs
    end

    -- Classic Era / Mists Classic define AccountBankTab_1..5 alongside legacy BankBag_1..7
    -- without CharacterBankTab_*; only use Enum.BagIndex fallback on modern bank layouts.
    local bagIndex = Enum and Enum.BagIndex --[[@as table<string, number?>]]
    if type(bagIndex) == "table" and type(bagIndex["CharacterBankTab_1"]) == "number" then
        local enumTabs = CollectEnumBankTabIDs("AccountBankTab_")
        if #enumTabs > 0 then
            return enumTabs
        end
    end

    return {}
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
            return {
                stackCount = info.stackCount or 0,
                isLocked = info.isLocked or false,
                itemID = info.itemID,
                isBound = info.isBound or false,
                itemLink = info.hyperlink or info.hyperLink or info.itemLink
            }
        end
    end

    -- Fallback for Classic Era GetContainerItemInfo
    local legacyGetInfo = _G["GetContainerItemInfo"]
    if legacyGetInfo then
        local ret1, count, locked, _, _, _, link, _, _, itemID, isBound = legacyGetInfo(bag, slot)

        -- Safeguard: If GetContainerItemInfo returned a single table (e.g. redirected by another addon or wrapper)
        if type(ret1) == "table" then
            return {
                stackCount = ret1.stackCount or 0,
                isLocked = ret1.isLocked or false,
                itemID = ret1.itemID,
                isBound = ret1.isBound or false,
                itemLink = ret1.hyperlink or ret1.hyperLink or ret1.itemLink
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

--- Returns total number of slots in a container.
--- @param bag number Container ID
--- @return number numSlots
function APIAdapter.GetContainerNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end
    local legacyGetNumSlots = _G["GetContainerNumSlots"]
    if legacyGetNumSlots then
        return legacyGetNumSlots(bag) or 0
    end
    return 0
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

--- Clears cursor contents, returning items held on cursor to their source slots.
function APIAdapter.ClearCursor()
    local clearCursor = _G["ClearCursor"]
    if clearCursor then
        clearCursor()
    end
end

--- Queries specialty item family bitmask for an item link or ID.
--- @param itemInput? string|number Item ID or item link
--- @return number family Bitmask integer (0 for general items)
function APIAdapter.GetItemFamily(itemInput)
    if not itemInput then return 0 end
    if C_Item and C_Item.GetItemFamily then
        local family = C_Item.GetItemFamily(itemInput)
        if family then return family end
    end
    -- Fallback for legacy Classic client API where GetItemFamily is global
    local legacyGetFamily = _G["GetItemFamily"]
    if legacyGetFamily then
        local family = legacyGetFamily(itemInput)
        if family then return family end
    end
    return 0
end

--- Queries whether an item is flagged as a crafting reagent (17th return of GetItemInfo).
--- Fails closed (false) when itemInput is nil, uncached, or GetItemInfo is unavailable.
--- @param itemInput? string|number Item ID or item link
--- @return boolean isCraftingReagent
function APIAdapter.IsCraftingReagent(itemInput)
    if not itemInput then
        return false
    end
    if C_Item and C_Item.GetItemInfo then
        local isCraftingReagent = select(17, C_Item.GetItemInfo(itemInput))
        return isCraftingReagent == true
    elseif _G["GetItemInfo"] then
        local legacyGetItemInfo = _G["GetItemInfo"]
        local isCraftingReagent = select(17, legacyGetItemInfo(itemInput))
        return isCraftingReagent == true
    end
    return false
end

--- Returns specialty bag family bitmask for a container ID.
--- @param bag number Container ID
--- @return number family Specialty family bitmask (0 for general bags)
function APIAdapter.GetBagItemFamily(bag)
    if not bag or bag <= 0 then
        if Private.DebugLog then
            Private.DebugLog("GetBagItemFamily(%s): bag ID is invalid/backpack (<= 0), returning 0", tostring(bag))
        end
        return 0
    end

    local isReagentBag = IsReagentBag(bag)

    if C_Container and C_Container.GetContainerNumFreeSlots then
        local _, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
        if type(bagFamily) == "number" then
            if isReagentBag and bagFamily == 0 then
                if Private.DebugLog then
                    Private.DebugLog("GetBagItemFamily(%s): Reagent Bag reported family 0, returning %d", tostring(bag), REAGENT_BAG_FAMILY)
                end
                return REAGENT_BAG_FAMILY
            end
            if Private.DebugLog then
                Private.DebugLog("GetBagItemFamily(%s): GetContainerNumFreeSlots returned family = %s", tostring(bag), tostring(bagFamily))
            end
            return bagFamily
        end
    end

    if isReagentBag then
        if Private.DebugLog then
            Private.DebugLog("GetBagItemFamily(%s): Reagent Bag family unavailable, defaulting to %d", tostring(bag), REAGENT_BAG_FAMILY)
        end
        return REAGENT_BAG_FAMILY
    end

    if IsModernBankTab(bag) then
        if Private.DebugLog then
            Private.DebugLog("GetBagItemFamily(%s): modern virtual bank tab detected, returning 0", tostring(bag))
        end
        return 0
    end

    local invID = nil
    if C_Container and C_Container.ContainerIDToInventoryID then
        invID = C_Container.ContainerIDToInventoryID(bag)
    else
        local getInvID = _G["ContainerIDToInventoryID"]
        if getInvID then
            invID = getInvID(bag)
        end
    end

    if Private.DebugLog then
        Private.DebugLog("GetBagItemFamily(%s): mapped to invID = %s", tostring(bag), tostring(invID))
    end

    if invID then
        -- Query by numeric Item ID first: much more robust than link parsing and avoids caching/loading delays
        local getInvItemID = _G["GetInventoryItemID"]
        if getInvItemID then
            local bagItemID = getInvItemID("player", invID)
            if Private.DebugLog then
                Private.DebugLog("GetBagItemFamily(%s): getInvItemID returned item ID = %s", tostring(bag), tostring(bagItemID))
            end
            if bagItemID and bagItemID > 0 then
                local family = APIAdapter.GetItemFamily(bagItemID)
                if Private.DebugLog then
                    Private.DebugLog("GetBagItemFamily(%s): GetItemFamily of item ID %s returned family = %s", tostring(bag), tostring(bagItemID), tostring(family))
                end
                if family and family ~= 0 then
                    return family
                end
            end
        end

        -- Fallback to Item Link if ID querying returned 0 or wasn't available
        local getInvLink = _G["GetInventoryItemLink"]
        if getInvLink then
            local bagLink = getInvLink("player", invID)
            if Private.DebugLog then
                Private.DebugLog("GetBagItemFamily(%s): getInvLink returned link = %s", tostring(bag), tostring(bagLink))
            end
            if bagLink then
                local family = APIAdapter.GetItemFamily(bagLink)
                if Private.DebugLog then
                    Private.DebugLog("GetBagItemFamily(%s): GetItemFamily of item link returned family = %s", tostring(bag), tostring(family))
                end
                if family and family ~= 0 then
                    return family
                end
            end
        end
    end
    if Private.DebugLog then
        Private.DebugLog("GetBagItemFamily(%s): failed to resolve family, returning 0", tostring(bag))
    end
    return 0
end

--- Checks whether an item at (bag, slot) is allowed in the specified bank type.
--- Returns true when C_Bank.IsItemAllowedInBankType or ItemLocation is unavailable
--- (for example, Classic clients or headless tests without ItemLocation).
--- @param bankType number Enum.BankType value
--- @param bag number Container ID
--- @param slot number Slot index
--- @return boolean isAllowed
function APIAdapter.IsItemAllowedInBankType(bankType, bag, slot)
    if bankType == nil or bag == nil or slot == nil then
        return false
    end
    if C_Bank and C_Bank.IsItemAllowedInBankType then
        local itemLocationFactory = _G["ItemLocation"]
        if type(itemLocationFactory) == "table" and type(itemLocationFactory.CreateFromBagAndSlot) == "function" then
            local itemLocation = itemLocationFactory:CreateFromBagAndSlot(bag, slot)
            if itemLocation ~= nil then
                return not not C_Bank.IsItemAllowedInBankType(bankType, itemLocation)
            end
        end
    end
    return true
end

return APIAdapter
