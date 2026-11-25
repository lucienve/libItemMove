-- Mock WoW Environment for Unit Testing
_G.LibStub = {}
local libraries = {}

function _G.LibStub:NewLibrary(major, minor)
    if libraries[major] then
        return nil
    end
    libraries[major] = {}
    return libraries[major]
end

function _G.LibStub:GetLibrary(major, silent)
    return libraries[major]
end

-- Mock CallbackHandler-1.0
local mockCallbackHandler = {}
function mockCallbackHandler:New(target)
    target.registeredCallbacks = {}
    return {
        Fire = function(_, event, ...)
            local cb = target.registeredCallbacks[event]
            if cb then cb(event, ...) end
        end
    }
end
libraries["CallbackHandler-1.0"] = mockCallbackHandler

-- Mock WoW API Globals
_G.NUM_BAG_SLOTS = 4
_G.NUM_BANKBAGSLOTS = 7

local currentTime = 1000.0
_G.GetTime = function()
    currentTime = currentTime + 0.05
    return currentTime
end

local cursorState = nil
local cursorItemId = nil
local cursorSrcInfo = nil
_G.GetCursorInfo = function()
    return cursorState, cursorItemId
end

_G.ClearCursor = function()
    if cursorSrcInfo then
        cursorSrcInfo.heldSplit = nil
    end
    cursorState = nil
    cursorItemId = nil
    cursorSrcInfo = nil
end

local frameScript = nil
local frameShown = false
local registeredEvents = {}
local pendingEvents = {}
local activeGuildBankTab = 1
local mockContainers

local function ProcessMockEvents()
    local events = pendingEvents
    pendingEvents = {}
    for _, event in ipairs(events) do
        local frames = registeredEvents[event]
        if frames then
            for _, f in ipairs(frames) do
                if f.onEvent then
                    f:onEvent(event)
                end
            end
        end
    end
end

_G.CreateFrame = function(typeStr)
    local f = {
        Show = function(self)
            if self.isScheduler then
                frameShown = true
            end
        end,
        Hide = function(self)
            if self.isScheduler then
                frameShown = false
            end
        end,
        RegisterEvent = function(self, event)
            if not registeredEvents[event] then
                registeredEvents[event] = {}
            end
            table.insert(registeredEvents[event], self)
        end,
        UnregisterAllEvents = function(self)
            for event, frames in pairs(registeredEvents) do
                for i = #frames, 1, -1 do
                    if frames[i] == self then
                        table.remove(frames, i)
                    end
                end
            end
        end,
        SetScript = function(self, event, fn)
            if event == "OnUpdate" then
                self.isScheduler = true
                frameShown = true
                frameScript = function(s, el)
                    ProcessMockEvents()
                    fn(s, el)
                end
            elseif event == "OnEvent" then
                self.onEvent = fn
            end
        end
    }
    return f
end

_G.GetCurrentGuildBankTab = function()
    return activeGuildBankTab
end

_G.SetCurrentGuildBankTab = function(tab)
    activeGuildBankTab = tab
end

_G.GetGuildBankTabInfo = function(tab)
    return "Tab " .. tab, "icon", true, true, 10, -1
end

_G.QueryGuildBankTab = function(tab)
    table.insert(pendingEvents, "GUILDBANKBAGSLOTS_CHANGED")
end

local mockGuildBank = {
    [2] = {},
    [3] = {}
}

_G.GetGuildBankItemInfo = function(tab, slot)
    if mockGuildBank[tab] and mockGuildBank[tab][slot] then
        local info = mockGuildBank[tab][slot]
        return nil, info.stackCount or 0
    end
    return nil, 0
end

_G.GetGuildBankItemLink = function(tab, slot)
    if mockGuildBank[tab] and mockGuildBank[tab][slot] then
        local info = mockGuildBank[tab][slot]
        if info.stackCount and info.stackCount > 0 then
            return info.itemLink
        end
    end
    return nil
end

_G.SplitGuildBankItem = function(tab, slot, count)
    local info = mockGuildBank[tab] and mockGuildBank[tab][slot]
    if info and info.stackCount and info.stackCount > 0 then
        cursorState = "item"
        cursorItemId = info.itemID
        cursorSrcInfo = info
        info.heldSplit = count
    end
end

_G.PickupGuildBankItem = function(tab, slot)
    if cursorState == "item" then
        local srcInfo = cursorSrcInfo or mockContainers[0][1]
        local movedQty = srcInfo.heldSplit or 10
        srcInfo.stackCount = srcInfo.stackCount - movedQty
        srcInfo.heldSplit = nil

        local id = cursorItemId or 12345
        if not mockGuildBank[tab] then mockGuildBank[tab] = {} end
        if mockGuildBank[tab][slot] and mockGuildBank[tab][slot].itemID == id then
            mockGuildBank[tab][slot].stackCount = mockGuildBank[tab][slot].stackCount + movedQty
        else
            mockGuildBank[tab][slot] = {
                itemID = id,
                stackCount = movedQty,
                itemLink = "item:" .. id
            }
        end

        cursorState = nil
        cursorItemId = nil
        cursorSrcInfo = nil
    end
end


-- Mock Container Data
mockContainers = {
    [0] = { -- Player Bag 0
        [1] = { itemID = 12345, stackCount = 20, isLocked = false, isBound = false, hyperlink = "item:12345" }
    },
    [-1] = { -- Bank Main Container
        [1] = { itemID = nil, stackCount = 0, isLocked = false, isBound = false }
    }
}

_G.C_Container = {
    GetContainerNumSlots = function(bag)
        if bag == 0 then return 4 end
        if bag == -1 then return 4 end
        return 0
    end,
    GetContainerItemInfo = function(bag, slot)
        if mockContainers[bag] and mockContainers[bag][slot] then
            local info = mockContainers[bag][slot]
            if info and info.stackCount and info.stackCount > 0 then
                return info
            end
        end
        return nil
    end,
    GetContainerItemID = function(bag, slot)
        local info = _G.C_Container.GetContainerItemInfo(bag, slot)
        return info and info.itemID
    end,
    SplitContainerItem = function(bag, slot, count)
        local info = mockContainers[bag] and mockContainers[bag][slot]
        if info and info.stackCount and info.stackCount > 0 then
            cursorState = "item"
            cursorItemId = info.itemID
            cursorSrcInfo = info
            info.heldSplit = count
        end
    end,
    PickupContainerItem = function(bag, slot)
        if cursorState == "item" then
            local srcInfo = cursorSrcInfo or mockContainers[0][1]
            local movedQty = srcInfo.heldSplit or 15
            srcInfo.stackCount = srcInfo.stackCount - movedQty
            srcInfo.heldSplit = nil

            local id = cursorItemId or 12345
            if not mockContainers[bag] then mockContainers[bag] = {} end
            if mockContainers[bag][slot] and mockContainers[bag][slot].itemID == id then
                mockContainers[bag][slot].stackCount = mockContainers[bag][slot].stackCount + movedQty
            else
                mockContainers[bag][slot] = {
                    itemID = id,
                    stackCount = movedQty,
                    isLocked = false,
                    isBound = false,
                    hyperlink = "item:" .. id
                }
            end

            cursorState = nil
            cursorItemId = nil
            cursorSrcInfo = nil
        end
    end,
    ContainerIDToInventoryID = function(bag) return nil end
}

_G.C_Item = {
    GetItemFamily = function(item) return 0 end,
    GetItemMaxStackSizeByID = function(item) return 20 end
}

-- Load Addon Files
local Private = {}
local function dofile_env(path)
    local chunk, err = loadfile(path)
    if not chunk then error("Failed to load " .. path .. ": " .. tostring(err)) end
    chunk("LibItemMove", Private)
end

dofile_env("core/utils.lua")
dofile_env("core/api_adapter.lua")
dofile_env("core/scheduler.lua")
dofile_env("contexts/base_context.lua")
dofile_env("contexts/bag_to_bank.lua")
dofile_env("contexts/bank_to_bag.lua")
dofile_env("contexts/bag_to_guildbank.lua")
dofile_env("contexts/guildbank_to_bag.lua")
dofile_env("contexts/bag_to_warbank.lua")
dofile_env("contexts/warbank_to_bag.lua")
dofile_env("mover.lua")
local lib = loadfile("LibItemMove.lua")("LibItemMove", Private)

-- Unit Tests Assertions
print("=== Running LibItemMove Unit Tests ===")

-- Test 1: SlotId Encoding & Decoding (including negative bank containers)
local slotId1 = lib.encode_bagslot(10, 100)
assert(slotId1 == 10100, "encode_bagslot failed: expected 10100")
local bag1, slot1 = lib.decode_bagslot(10100)
assert(bag1 == 10 and slot1 == 100, "decode_bagslot failed: expected 10, 100")

local slotId2 = lib.encode_bagslot(-1, 5)
assert(slotId2 == -995, "encode_bagslot failed for Bank: expected -995")
local bag2, slot2 = lib.decode_bagslot(-995)
assert(bag2 == -1 and slot2 == 5, "decode_bagslot failed for Bank: expected -1, 5")
print("[PASS] SlotId Encoding & Decoding test passed.")

-- Test 2: Dynamic Classic Era Container ID Resolution
local playerBags = Private.APIAdapter.GetPlayerBagIDs()
assert(#playerBags == 5 and playerBags[5] == 4, "Classic Era player bags resolution failed: expected 0..4")

local bankContainers = Private.APIAdapter.GetBankContainerIDs()
assert(bankContainers[1] == -1 and bankContainers[2] == 5, "Classic Era bank containers resolution failed: expected 5 to be first bank bag")
print("[PASS] Dynamic Classic Era Container ID Resolution test passed.")

-- Test 2b: Reagent Bank (-3) Guard & Retail Reagent Bag Resolution
_G.REAGENTBANK_CONTAINER = -3
local bankContainersMists = Private.APIAdapter.GetBankContainerIDs()
local hasReagentBankMists = false
for _, id in ipairs(bankContainersMists) do
    if id == -3 then hasReagentBankMists = true end
end
assert(hasReagentBankMists == false, "Mists Classic must not include Reagent Bank (-3) when IsReagentBankUnlocked is absent")

_G.IsReagentBankUnlocked = function() return false end
local bankContainersLocked = Private.APIAdapter.GetBankContainerIDs()
local hasReagentBankLocked = false
for _, id in ipairs(bankContainersLocked) do
    if id == -3 then hasReagentBankLocked = true end
end
assert(hasReagentBankLocked == false, "Reagent Bank (-3) must not be included when IsReagentBankUnlocked returns false")

_G.IsReagentBankUnlocked = function() return true end
local bankContainersUnlocked = Private.APIAdapter.GetBankContainerIDs()
local hasReagentBankUnlocked = false
for _, id in ipairs(bankContainersUnlocked) do
    if id == -3 then hasReagentBankUnlocked = true end
end
assert(hasReagentBankUnlocked == true, "Reagent Bank (-3) must be included when IsReagentBankUnlocked returns true")
_G.IsReagentBankUnlocked = nil
_G.REAGENTBANK_CONTAINER = nil

_G.NUM_REAGENTBAG_SLOTS = 1
local playerBagsRetail = Private.APIAdapter.GetPlayerBagIDs()
assert(#playerBagsRetail == 6 and playerBagsRetail[6] == 5, "Retail player bags must include bag 5 when NUM_REAGENTBAG_SLOTS == 1")
local bankContainersRetail = Private.APIAdapter.GetBankContainerIDs()
assert(bankContainersRetail[1] == -1 and bankContainersRetail[2] == 6, "Retail bank bags must start at 6 when NUM_REAGENTBAG_SLOTS == 1")
_G.NUM_REAGENTBAG_SLOTS = nil
print("[PASS] Reagent Bank (-3) Guard & Retail Reagent Bag Resolution test passed.")

-- Test 3: Robust Single-Table Return Protection for GetContainerItemInfo
local rawSingleTableHook = function(bag, slot)
    return { itemID = 555, stackCount = 10, isBound = true, hyperlink = "item:555" }
end

_G.GetContainerItemInfo = rawSingleTableHook
local tmpCContainer = _G.C_Container
_G.C_Container = nil -- Simulate legacy environment with overridden GetContainerItemInfo

local infoSingle = Private.APIAdapter.GetContainerItemInfo(1, 1)
assert(infoSingle ~= nil and infoSingle.itemID == 555 and infoSingle.isBound == true and infoSingle.itemLink == "item:555", "Single-table fallback hook protection failed!")
_G.C_Container = tmpCContainer
_G.GetContainerItemInfo = nil

-- Test C_Container lowercase hyperlink normalization
local adapterInfo = Private.APIAdapter.GetContainerItemInfo(0, 1)
assert(adapterInfo ~= nil and adapterInfo.itemLink == "item:12345", "APIAdapter failed to normalize lowercase hyperlink to itemLink")
print("[PASS] Single-table return protection and lowercase hyperlink normalization test passed.")

-- Test 4: Item ID Parsing & Strict Matching
local id1 = Private.Utils.GetItemIdFromString("i:12345")
local id2 = Private.Utils.GetItemIdFromString("item:12345:0:0")
assert(id1 == 12345 and id2 == 12345, "GetItemIdFromString failed")

local match1 = Private.Utils.IsItemMatching("item:12345:100:0", { itemID = 12345, itemLink = "item:12345:100:0" })
local match2 = Private.Utils.IsItemMatching("item:12345:200:0", { itemID = 12345, itemLink = "item:12345:100:0" })
assert(match1 == true and match2 == false, "Strict item link variant matching failed")
print("[PASS] Item ID Parsing & Strict Matching test passed.")

-- Test 5: Specialty Bag Family Compatibility
assert(Private.Utils.IsFamilyCompatible(4, 0) == true, "General bag compatibility failed")
assert(Private.Utils.IsFamilyCompatible(4, 4) == true, "Herb bag matching failed")
assert(Private.Utils.IsFamilyCompatible(4, 8) == false, "Mining vs Herb mismatch failed")
print("[PASS] Item Family Compatibility test passed.")

-- Test 6: Cursor Hold Early Abort Check
cursorState = "item"
cursorItemId = 9999
local cursorErrorFired = false
lib:Move({ ["i:12345"] = 5 }, "BagToBank", function(event)
    if event == "CURSOR_LOCKED_ERROR" then cursorErrorFired = true end
end)
if frameScript then frameScript(nil, 0.05) end
assert(cursorErrorFired == true, "Cursor hold early abort failed")
cursorState = nil
cursorItemId = nil
print("[PASS] Cursor Hold Early Abort test passed.")

-- Test 7: Guild Bank vs Player Bag API Mapping test passed
local b2gb = Private.BagToGuildBank
local originalGetGuildBankItemInfo = _G.GetGuildBankItemInfo
_G.GetGuildBankItemInfo = function(tab, slot) return nil, 77 end
assert(b2gb:GetSourceSlotQuantity(lib.encode_bagslot(0, 1)) == 20, "BagToGuildBank source slot quantity must call container bag API")
assert(b2gb:GetTargetSlotQuantity(lib.encode_bagslot(1, 1)) == 77, "BagToGuildBank target slot quantity must call Guild Bank API")
_G.GetGuildBankItemInfo = originalGetGuildBankItemInfo
print("[PASS] Guild Bank vs Player Bag API Mapping test passed.")

-- Test 8: Scheduler Concurrency Protection
Private.Scheduler.active = true
Private.Scheduler.thread = coroutine.create(function() end)
local concurrencyCaught = false
local ok, err = pcall(function()
    lib:Move({ ["i:12345"] = 1 }, "BagToBank")
end)
if not ok and err:find("already in progress") then
    concurrencyCaught = true
end
Private.Scheduler.active = false
Private.Scheduler.thread = nil
assert(concurrencyCaught == true, "Scheduler concurrency protection failed")
print("[PASS] Scheduler Concurrency Protection test passed.")

-- Test 9: Asynchronous Cooperative Move Execution & Stack Verification
local progressEvents = {}
local moveCompleted = false

lib:Move({ ["i:12345"] = 15 }, "BagToBank", function(event, item, qty)
    table.insert(progressEvents, { event = event, item = item, qty = qty })
    if event == "DONE" then
        moveCompleted = true
    end
end)

-- Drive the coroutine through frame ticks
local ticks = 0
while frameShown and ticks < 20 do
    ticks = ticks + 1
    if frameScript then
        frameScript(nil, 0.05)
    end
end

assert(moveCompleted == true, "Move coroutine failed to complete within ticks")
assert(mockContainers[0][1].stackCount == 5, "Source bag quantity failed to reduce to 5")
assert(mockContainers[-1][1].stackCount == 15, "Destination bank quantity failed to reach 15")
print("[PASS] Asynchronous Cooperative Move Execution test passed!")

-- Test 10: Sequential Multi-Tab Guild Bank Movement
mockContainers[0][1] = { itemID = 12345, stackCount = 20, isLocked = false, isBound = false, hyperlink = "item:12345" }
mockGuildBank[2] = {}
mockGuildBank[3] = {}
activeGuildBankTab = 1

local multiQueue = {
    [2] = {
        ["i:12345"] = 10
    },
    [3] = {
        ["i:12345"] = 5
    }
}

local multiProgressEvents = {}
local multiMoveCompleted = false

lib:Move(multiQueue, "BagToGuildBank", function(event, item, qty)
    table.insert(multiProgressEvents, { event = event, item = item, qty = qty })
    if event == "DONE" then
        multiMoveCompleted = true
    end
end)

-- Drive the coroutine through frame ticks
ticks = 0
while frameShown and ticks < 50 do
    ticks = ticks + 1
    if frameScript then
        frameScript(nil, 0.05)
    end
end

assert(multiMoveCompleted == true, "Multi-tab move coroutine failed to complete")
assert(mockContainers[0][1].stackCount == 5, "Multi-tab source bag stack count failed to reduce to 5")
assert(mockGuildBank[2][1] and mockGuildBank[2][1].stackCount == 10, "Tab 2 target quantity failed to reach 10")
assert(mockGuildBank[3][1] and mockGuildBank[3][1].stackCount == 5, "Tab 3 target quantity failed to reach 5")
print("[PASS] Sequential Multi-Tab Guild Bank Movement test passed!")

-- Test 11: GetBagItemFamily Resolution
local originalContainerIDToInventoryID = _G.C_Container.ContainerIDToInventoryID
local originalGetInventoryItemID = _G.GetInventoryItemID
local originalGetItemFamily = Private.APIAdapter.GetItemFamily

_G.C_Container.ContainerIDToInventoryID = function(bag)
    if bag == 5 then return 68 end -- Slot for Mammoth Mining Bag
    return nil
end

_G.GetInventoryItemID = function(unit, slot)
    if unit == "player" and slot == 68 then
        return 44446 -- Mammoth Mining Bag Item ID
    end
    return nil
end

Private.APIAdapter.GetItemFamily = function(itemInput)
    if itemInput == 44446 then
        return 1024 -- Mining bag family
    end
    return 0
end

local family = Private.APIAdapter.GetBagItemFamily(5)
assert(family == 1024, "GetBagItemFamily failed to resolve equipped bag family: expected 1024, got " .. tostring(family))

-- Restore mocks
_G.C_Container.ContainerIDToInventoryID = originalContainerIDToInventoryID
_G.GetInventoryItemID = originalGetInventoryItemID
Private.APIAdapter.GetItemFamily = originalGetItemFamily
print("[PASS] GetBagItemFamily Resolution test passed.")

-- Test 12: Multi-Split Consolidation (First to partial stack, then remainder to empty slot)
mockContainers[0] = {
    [1] = { itemID = 888, stackCount = 20, isLocked = false, isBound = false, hyperlink = "item:888" }
}
mockGuildBank[2] = {
    [1] = { itemID = 888, stackCount = 6, itemLink = "item:888", isLocked = false, isBound = false }
}
activeGuildBankTab = 2

local test12Completed = false
lib:Move({ ["i:888"] = 20 }, "BagToGuildBank", function(event)
    if event == "DONE" then
        test12Completed = true
    end
end)

ticks = 0
while frameShown and ticks < 50 do
    ticks = ticks + 1
    if frameScript then
        frameScript(nil, 0.05)
    end
end

assert(test12Completed == true, "Test 12: Multi-split move failed to complete")
assert(mockContainers[0][1] == nil or mockContainers[0][1].stackCount == 0, "Test 12: Source slot failed to be cleared")
assert(mockGuildBank[2][1] and mockGuildBank[2][1].stackCount == 20, "Test 12: Target slot 1 failed to reach 20")
assert(mockGuildBank[2][2] and mockGuildBank[2][2].stackCount == 6, "Test 12: Target slot 2 failed to receive remainder of 6")
print("[PASS] Multi-Split Consolidation test passed.")

-- Test 13: Centralized APIAdapter.GetContainerNumSlots Resolution
assert(Private.APIAdapter.GetContainerNumSlots(0) == 4, "Test 13: Bag 0 slots failed, expected 4")
assert(Private.APIAdapter.GetContainerNumSlots(-1) == 4, "Test 13: Bank slots failed, expected 4")
assert(Private.APIAdapter.GetContainerNumSlots(99) == 0, "Test 13: Nonexistent container should return 0")
print("[PASS] APIAdapter.GetContainerNumSlots Resolution test passed.")

-- Test 14: Warbank & Modern Character Bank Container Resolution (Retail, WoW Forever, Classic)
local b2w = Private.BagToWarbank
local w2b = Private.WarbankToBag
local origCBank = _G.C_Bank
local origEnum = _G.Enum
local origGetContainerNumSlots = _G.C_Container.GetContainerNumSlots

-- 14a: Absent C_Bank and absent Enum.BagIndex returns empty Warbank containers
_G.C_Bank = nil
_G.Enum = nil
local emptyWarbankB2W = b2w:GetWarbankContainers()
local emptyWarbankW2B = w2b:GetWarbankContainers()
assert(#emptyWarbankB2W == 0, "Test 14a: BagToWarbank should return {} when C_Bank and Enum are absent")
assert(#emptyWarbankW2B == 0, "Test 14a: WarbankToBag should return {} when C_Bank and Enum are absent")

-- 14b: Retail Enum.BagIndex fallback (CharacterBankTab_1..6 = 6..11, AccountBankTab_1..5 = 12..16)
_G.Enum = {
    BagIndex = {
        CharacterBankTab_1 = 6,
        CharacterBankTab_2 = 7,
        CharacterBankTab_3 = 8,
        CharacterBankTab_4 = 9,
        CharacterBankTab_5 = 10,
        CharacterBankTab_6 = 11,
        AccountBankTab_1 = 12,
        AccountBankTab_2 = 13,
        AccountBankTab_3 = 14,
        AccountBankTab_4 = 15,
        AccountBankTab_5 = 16,
    }
}
local retailBankEnum = Private.APIAdapter.GetBankContainerIDs()
assert(#retailBankEnum == 6 and retailBankEnum[1] == 6 and retailBankEnum[6] == 11,
    "Test 14b: Retail Enum.BagIndex fallback should resolve CharacterBankTab 6..11")
local retailWarbankB2W = b2w:GetWarbankContainers()
local retailWarbankW2B = w2b:GetWarbankContainers()
assert(#retailWarbankB2W == 5 and retailWarbankB2W[1] == 12 and retailWarbankB2W[5] == 16,
    "Test 14b: Retail BagToWarbank fallback should resolve AccountBankTab 12..16")
assert(#retailWarbankW2B == 5 and retailWarbankW2B[1] == 12 and retailWarbankW2B[5] == 16,
    "Test 14b: Retail WarbankToBag fallback should resolve AccountBankTab 12..16")

-- 14c: WoW Forever Enum.BagIndex fallback (CharacterBankTab_1..9 = 6..14, AccountBankTab_1..9 = 15..23)
_G.Enum = {
    BagIndex = {
        Keyring = -1,
        CharacterBankTab_1 = 6,
        CharacterBankTab_2 = 7,
        CharacterBankTab_3 = 8,
        CharacterBankTab_4 = 9,
        CharacterBankTab_5 = 10,
        CharacterBankTab_6 = 11,
        CharacterBankTab_7 = 12,
        CharacterBankTab_8 = 13,
        CharacterBankTab_9 = 14,
        AccountBankTab_1 = 15,
        AccountBankTab_2 = 16,
        AccountBankTab_3 = 17,
        AccountBankTab_4 = 18,
        AccountBankTab_5 = 19,
        AccountBankTab_6 = 20,
        AccountBankTab_7 = 21,
        AccountBankTab_8 = 22,
        AccountBankTab_9 = 23,
    }
}
local foreverBankEnum = Private.APIAdapter.GetBankContainerIDs()
assert(#foreverBankEnum == 9 and foreverBankEnum[1] == 6 and foreverBankEnum[9] == 14,
    "Test 14c: Forever Enum.BagIndex fallback should resolve CharacterBankTab 6..14")
local foreverWarbankB2W = b2w:GetWarbankContainers()
local foreverWarbankW2B = w2b:GetWarbankContainers()
assert(#foreverWarbankB2W == 9 and foreverWarbankB2W[1] == 15 and foreverWarbankB2W[9] == 23,
    "Test 14c: Forever BagToWarbank fallback should resolve AccountBankTab 15..23")
assert(#foreverWarbankW2B == 9 and foreverWarbankW2B[1] == 15 and foreverWarbankW2B[9] == 23,
    "Test 14c: Forever WarbankToBag fallback should resolve AccountBankTab 15..23")

-- 14d: Dynamic C_Bank querying on Retail
_G.C_Bank = {
    FetchPurchasedBankTabIDs = function(bankType)
        if bankType == 2 then -- Enum.BankType.Account
            return { 12, 13 }
        elseif bankType == 0 then -- Enum.BankType.Character
            return { 6, 7, 8 }
        end
        return {}
    end,
    CanUseBank = function(bankType)
        return bankType == 2
    end
}

local activeWarbankTabs = b2w:GetWarbankContainers()
assert(#activeWarbankTabs == 2 and activeWarbankTabs[1] == 12 and activeWarbankTabs[2] == 13,
    "Test 14d: Dynamic Warbank tab query failed")
assert(b2w:HasPermission() == true, "Test 14d: Warbank permission check failed")

local modernBankTabs = Private.APIAdapter.GetBankContainerIDs()
assert(#modernBankTabs == 3 and modernBankTabs[1] == 6 and modernBankTabs[3] == 8,
    "Test 14d: Dynamic modern bank tabs query failed")

-- 14e: Dynamic C_Bank querying on WoW Forever (9-tab Camelot layout + ShouldUsePlayerBagsInBank)
_G.Enum.BankType = { Character = 0, Guild = 1, Account = 2 }
_G.C_Bank = {
    ShouldUsePlayerBagsInBank = function()
        return true
    end,
    FetchPurchasedBankTabIDs = function(bankType)
        if bankType == 0 then
            return { 6, 7, 8, 9, 10, 11, 12, 13, 14 }
        elseif bankType == 2 then
            return { 15, 16, 17, 18, 19, 20, 21, 22, 23 }
        end
        return {}
    end,
    CanUseBank = function(bankType)
        return bankType == 0 or bankType == 2
    end
}
local foreverBankDynamic = Private.APIAdapter.GetBankContainerIDs()
assert(#foreverBankDynamic == 9 and foreverBankDynamic[1] == 6 and foreverBankDynamic[9] == 14,
    "Test 14e: Forever dynamic bank tabs should return 6..14")
local foreverWarbankDynB2W = b2w:GetWarbankContainers()
local foreverWarbankDynW2B = w2b:GetWarbankContainers()
assert(#foreverWarbankDynB2W == 9 and foreverWarbankDynB2W[1] == 15 and foreverWarbankDynB2W[9] == 23,
    "Test 14e: Forever dynamic BagToWarbank tabs should return 15..23")
assert(#foreverWarbankDynW2B == 9 and foreverWarbankDynW2B[1] == 15 and foreverWarbankDynW2B[9] == 23,
    "Test 14e: Forever dynamic WarbankToBag tabs should return 15..23")

-- Verify unequipped Camelot bank bag slot (0 slots) is skipped while tab 9 (14) is scanned
_G.C_Container.GetContainerNumSlots = function(bag)
    if bag == 14 then return 2 end
    return 0
end
local foreverEmptySlots = {}
Private.BagToBank:GetEmptySlots(foreverEmptySlots)
assert(#foreverEmptySlots == 2 and foreverEmptySlots[1] == 14001 and foreverEmptySlots[2] == 14002,
    "Test 14e: BagToBank:GetEmptySlots should skip unequipped 0-slot tabs and scan tab 14")
_G.C_Container.GetContainerNumSlots = origGetContainerNumSlots

-- 14f: Zero-purchased-tabs must return {} without falling back to Enum.BagIndex or colliding on 12..14
_G.C_Bank = {
    FetchPurchasedBankTabIDs = function()
        return {}
    end
}
local zeroBankTabs = Private.APIAdapter.GetBankContainerIDs()
local zeroWarbankB2W = b2w:GetWarbankContainers()
local zeroWarbankW2B = w2b:GetWarbankContainers()
assert(#zeroBankTabs == 0, "Test 14f: 0 purchased character bank tabs must return {}")
assert(#zeroWarbankB2W == 0, "Test 14f: 0 purchased warbank tabs (BagToWarbank) must return {}")
assert(#zeroWarbankW2B == 0, "Test 14f: 0 purchased warbank tabs (WarbankToBag) must return {}")

-- 14g: Classic Enum.BagIndex regression (no CharacterBankTab_* -> falls through to legacy -1, 5..11)
_G.C_Bank = nil
_G.Enum = {
    BagIndex = {
        Bank = -1,
        BankBag_1 = 6,
        BankBag_2 = 7,
        BankBag_3 = 8,
        BankBag_4 = 9,
        BankBag_5 = 10,
        BankBag_6 = 11,
        BankBag_7 = 12,
        AccountBankTab_1 = 13,
        AccountBankTab_2 = 14,
        AccountBankTab_3 = 15,
        AccountBankTab_4 = 16,
        AccountBankTab_5 = 17,
    }
}
local classicBankFallback = Private.APIAdapter.GetBankContainerIDs()
assert(#classicBankFallback == 8 and classicBankFallback[1] == -1 and classicBankFallback[2] == 5 and classicBankFallback[8] == 11,
    "Test 14g: Classic Enum.BagIndex should fall through to legacy bank layout -1 and 5..11")

_G.C_Bank = origCBank
_G.Enum = origEnum
print("[PASS] Warbank & Modern Character Bank Container Resolution test passed.")

-- Test 15a: Sequential Partial-Stack Accumulation (BagToGuildBank delayed confirmation)
mockContainers[0] = {
    [1] = { itemID = 12345, stackCount = 10, isLocked = false, isBound = false, hyperlink = "item:12345" },
    [2] = { itemID = 12345, stackCount = 5, isLocked = false, isBound = false, hyperlink = "item:12345" }
}
mockGuildBank[2] = {
    [1] = { itemID = 12345, stackCount = 5, itemLink = "item:12345" }
}
activeGuildBankTab = 2

local origPickupGuildBankItem = _G.PickupGuildBankItem
local move2Intercepted = false
_G.PickupGuildBankItem = function(tab, slot)
    if cursorState == "item" and cursorSrcInfo == mockContainers[0][2] then
        move2Intercepted = true
        local movedQty = cursorSrcInfo.heldSplit or 5
        cursorSrcInfo.stackCount = cursorSrcInfo.stackCount - movedQty
        cursorSrcInfo.heldSplit = nil
        cursorState = nil
        cursorItemId = nil
        cursorSrcInfo = nil
        return
    end
    origPickupGuildBankItem(tab, slot)
end

local test15aProgressCount = 0
local test15aTimeout = false
local test15aDone = false

lib:Move({ ["i:12345"] = 15 }, "BagToGuildBank", function(event)
    if event == "PROGRESS" then
        test15aProgressCount = test15aProgressCount + 1
    elseif event == "TIMEOUT_ERROR" then
        test15aTimeout = true
    elseif event == "DONE" then
        test15aDone = true
    end
end)

ticks = 0
while frameShown and not move2Intercepted and ticks < 50 do
    ticks = ticks + 1
    if frameScript then
        frameScript(nil, 0.05)
    end
end
assert(move2Intercepted == true, "Test 15a: Move 2 was not intercepted")

for _ = 1, 3 do
    if frameShown and frameScript then
        frameScript(nil, 0.05)
    end
    assert(test15aProgressCount == 1, "Test 15a: Premature PROGRESS before Move 2 destination confirmation")
    assert(test15aDone == false, "Test 15a: Premature DONE before Move 2 destination confirmation")
    assert(mockGuildBank[2][1].stackCount == 15, "Test 15a: Destination stack should remain 15 during delay")
end

-- Apply delayed server confirmation for Move 2
mockGuildBank[2][1].stackCount = mockGuildBank[2][1].stackCount + 5

ticks = 0
while frameShown and ticks < 50 do
    ticks = ticks + 1
    if frameScript then
        frameScript(nil, 0.05)
    end
end

_G.PickupGuildBankItem = origPickupGuildBankItem

assert(test15aDone == true, "Test 15a: BagToGuildBank move failed to complete")
assert(test15aTimeout == false, "Test 15a: Unexpected timeout occurred")
assert(test15aProgressCount == 2, "Test 15a: Expected 2 PROGRESS events, got " .. tostring(test15aProgressCount))
assert(mockContainers[0][1].stackCount == 0, "Test 15a: Source slot 1 failed to empty")
assert(mockContainers[0][2].stackCount == 0, "Test 15a: Source slot 2 failed to empty")
assert(mockGuildBank[2][1].stackCount == 20, "Test 15a: Target slot failed to reach 20")
print("[PASS] Sequential Partial-Stack Accumulation (BagToGuildBank delayed confirmation) test passed.")

-- Test 15b: Sequential Partial-Stack Accumulation (BagToBank dropped Move 2)
mockContainers[0] = {
    [1] = { itemID = 12345, stackCount = 10, isLocked = false, isBound = false, hyperlink = "item:12345" },
    [2] = { itemID = 12345, stackCount = 5, isLocked = false, isBound = false, hyperlink = "item:12345" }
}
mockContainers[-1] = {
    [1] = { itemID = 12345, stackCount = 5, isLocked = false, isBound = false, hyperlink = "item:12345" }
}

local origPickupContainerItem = _G.C_Container.PickupContainerItem
_G.C_Container.PickupContainerItem = function(bag, slot)
    if cursorState == "item" and cursorSrcInfo == mockContainers[0][2] then
        local movedQty = cursorSrcInfo.heldSplit or 5
        cursorSrcInfo.stackCount = cursorSrcInfo.stackCount - movedQty
        cursorSrcInfo.heldSplit = nil
        cursorState = nil
        cursorItemId = nil
        cursorSrcInfo = nil
        return
    end
    origPickupContainerItem(bag, slot)
end

local test15bProgressCount = 0
local test15bTimeout = false
local test15bDone = false

lib:Move({ ["i:12345"] = 15 }, "BagToBank", function(event)
    if event == "PROGRESS" then
        test15bProgressCount = test15bProgressCount + 1
    elseif event == "TIMEOUT_ERROR" then
        test15bTimeout = true
    elseif event == "DONE" then
        test15bDone = true
    end
end)

ticks = 0
while frameShown and ticks < 200 do
    ticks = ticks + 1
    if frameScript then
        frameScript(nil, 0.05)
    end
end

_G.C_Container.PickupContainerItem = origPickupContainerItem

assert(test15bTimeout == true, "Test 15b: Expected TIMEOUT_ERROR when Move 2 dropped")
assert(test15bDone == true, "Test 15b: Expected DONE after timeout handling")
assert(test15bProgressCount == 1, "Test 15b: Expected only 1 PROGRESS event, got " .. tostring(test15bProgressCount))
assert(mockContainers[-1][1].stackCount == 15, "Test 15b: Bank destination stack should remain 15")
print("[PASS] Sequential Partial-Stack Accumulation (BagToBank dropped Move 2) test passed.")

-- Test 16: MoP Classic / Classic Era Warbank Fail-Closed, Bank Offset, and Guild Bank Enabled Gate
local orig16CBank = _G.C_Bank
local orig16Enum = _G.Enum
local orig16CGuildBank = _G.C_GuildBank
local orig16BankBagOffset = _G.ITEM_INVENTORY_BANK_BAG_OFFSET
local orig16ReagentBagContainer = _G.REAGENTBAG_CONTAINER
local orig16NumReagentBagSlots = _G.NUM_REAGENTBAG_SLOTS
local orig16QueryGuildBankTab = _G.QueryGuildBankTab

-- 16a: Warbank fails closed without C_Bank and ignores Classic Enum.BagIndex AccountBankTab_*
_G.C_Bank = nil
_G.Enum = {
    BagIndex = {
        Bank = -1,
        Backpack = 0,
        Bag_1 = 1,
        Bag_2 = 2,
        Bag_3 = 3,
        Bag_4 = 4,
        ReagentBag = 5,
        BankBag_1 = 6,
        BankBag_2 = 7,
        BankBag_3 = 8,
        BankBag_4 = 9,
        BankBag_5 = 10,
        BankBag_6 = 11,
        BankBag_7 = 12,
        AccountBankTab_1 = 13,
        AccountBankTab_2 = 14,
        AccountBankTab_3 = 15,
        AccountBankTab_4 = 16,
        AccountBankTab_5 = 17,
    }
}

assert(Private.BagToWarbank:HasPermission() == false, "Test 16a: BagToWarbank:HasPermission must return false when C_Bank is nil")
assert(Private.WarbankToBag:HasPermission() == false, "Test 16a: WarbankToBag:HasPermission must return false when C_Bank is nil")

local classicWarbankContainers = Private.APIAdapter.GetWarbankContainerIDs()
assert(#classicWarbankContainers == 0, "Test 16a: Classic Enum.BagIndex must return {} for Warbank containers")

local b2wPermErr = false
local b2wDone = false
lib:Move({ ["i:12345"] = 1 }, "BagToWarbank", function(event)
    if event == "PERMISSION_ERROR" then b2wPermErr = true end
    if event == "DONE" then b2wDone = true end
end)
if frameScript then frameScript(nil, 0.05) end
assert(b2wPermErr == true, "Test 16a: BagToWarbank must emit PERMISSION_ERROR when C_Bank is nil")
assert(b2wDone == false, "Test 16a: BagToWarbank must not emit DONE on PERMISSION_ERROR")
assert(Private.Scheduler.active == false, "Test 16a: Scheduler must clear after BagToWarbank PERMISSION_ERROR")

local w2bPermErr = false
local w2bDone = false
lib:Move({ ["i:12345"] = 1 }, "WarbankToBag", function(event)
    if event == "PERMISSION_ERROR" then w2bPermErr = true end
    if event == "DONE" then w2bDone = true end
end)
if frameScript then frameScript(nil, 0.05) end
assert(w2bPermErr == true, "Test 16a: WarbankToBag must emit PERMISSION_ERROR when C_Bank is nil")
assert(w2bDone == false, "Test 16a: WarbankToBag must not emit DONE on PERMISSION_ERROR")
assert(Private.Scheduler.active == false, "Test 16a: Scheduler must clear after WarbankToBag PERMISSION_ERROR")

-- 16b: ITEM_INVENTORY_BANK_BAG_OFFSET precedence and fallback
_G.C_Bank = nil
_G.Enum = nil
_G.ITEM_INVENTORY_BANK_BAG_OFFSET = 4
_G.REAGENTBAG_CONTAINER = 5
local offset4Player = Private.APIAdapter.GetPlayerBagIDs()
assert(#offset4Player == 5 and offset4Player[5] == 4,
    "Test 16b: ITEM_INVENTORY_BANK_BAG_OFFSET=4 must keep player bags as 0..4 even if REAGENTBAG_CONTAINER=5")
local offset4Bank = Private.APIAdapter.GetBankContainerIDs()
assert(#offset4Bank == 8 and offset4Bank[1] == -1 and offset4Bank[2] == 5 and offset4Bank[8] == 11,
    "Test 16b: ITEM_INVENTORY_BANK_BAG_OFFSET=4 must resolve -1 and 5..11 even if REAGENTBAG_CONTAINER=5")

_G.ITEM_INVENTORY_BANK_BAG_OFFSET = 5
local offset5Bank = Private.APIAdapter.GetBankContainerIDs()
assert(#offset5Bank == 8 and offset5Bank[1] == -1 and offset5Bank[2] == 6 and offset5Bank[8] == 12,
    "Test 16b: ITEM_INVENTORY_BANK_BAG_OFFSET=5 must resolve -1 and 6..12")

_G.ITEM_INVENTORY_BANK_BAG_OFFSET = nil
_G.REAGENTBAG_CONTAINER = nil
local fallbackBank = Private.APIAdapter.GetBankContainerIDs()
assert(#fallbackBank == 8 and fallbackBank[1] == -1 and fallbackBank[2] == 5 and fallbackBank[8] == 11,
    "Test 16b: Fallback without ITEM_INVENTORY_BANK_BAG_OFFSET must resolve -1 and 5..11")

-- 16c: C_GuildBank.IsGuildBankEnabled() gate for single-tab and multi-tab moves
local guildBankEnabled = false
_G.C_GuildBank = {
    IsGuildBankEnabled = function()
        return guildBankEnabled
    end
}
local queryTabCallCount = 0
_G.QueryGuildBankTab = function(tab)
    queryTabCallCount = queryTabCallCount + 1
    orig16QueryGuildBankTab(tab)
end

assert(Private.BagToGuildBank:HasPermission() == false, "Test 16c: BagToGuildBank:HasPermission must return false when Guild Bank is disabled")
assert(Private.GuildBankToBag:HasPermission() == false, "Test 16c: GuildBankToBag:HasPermission must return false when Guild Bank is disabled")

local gb2bPermErr = false
local gb2bDone = false
lib:Move({ ["i:12345"] = 1 }, "GuildBankToBag", function(event)
    if event == "PERMISSION_ERROR" then gb2bPermErr = true end
    if event == "DONE" then gb2bDone = true end
end)
if frameScript then frameScript(nil, 0.05) end
assert(gb2bPermErr == true and gb2bDone == false and Private.Scheduler.active == false,
    "Test 16c: GuildBankToBag must emit PERMISSION_ERROR immediately when Guild Bank is disabled")

local b2gbPermErr = false
local b2gbDone = false
lib:Move({ ["i:12345"] = 1 }, "BagToGuildBank", function(event)
    if event == "PERMISSION_ERROR" then b2gbPermErr = true end
    if event == "DONE" then b2gbDone = true end
end)
if frameScript then frameScript(nil, 0.05) end
assert(b2gbPermErr == true and b2gbDone == false and Private.Scheduler.active == false,
    "Test 16c: BagToGuildBank must emit PERMISSION_ERROR immediately when Guild Bank is disabled")

activeGuildBankTab = 1
local multiGbPermErr = false
local multiGbDone = false
lib:Move({ [2] = { ["i:12345"] = 1 } }, "BagToGuildBank", function(event)
    if event == "PERMISSION_ERROR" then multiGbPermErr = true end
    if event == "DONE" then multiGbDone = true end
end)
if frameScript then frameScript(nil, 0.05) end
assert(multiGbPermErr == true and multiGbDone == false and Private.Scheduler.active == false,
    "Test 16c: Multi-tab BagToGuildBank must emit PERMISSION_ERROR immediately when Guild Bank is disabled")
assert(queryTabCallCount == 0, "Test 16c: Multi-tab BagToGuildBank must not query tabs when Guild Bank is disabled")

guildBankEnabled = true
assert(Private.BagToGuildBank:HasPermission() == true, "Test 16c: BagToGuildBank:HasPermission must succeed when Guild Bank is enabled")
assert(Private.GuildBankToBag:HasPermission() == true, "Test 16c: GuildBankToBag:HasPermission must succeed when Guild Bank is enabled")

-- Restore Test 16 globals
_G.C_Bank = orig16CBank
_G.Enum = orig16Enum
_G.C_GuildBank = orig16CGuildBank
_G.ITEM_INVENTORY_BANK_BAG_OFFSET = orig16BankBagOffset
_G.REAGENTBAG_CONTAINER = orig16ReagentBagContainer
_G.NUM_REAGENTBAG_SLOTS = orig16NumReagentBagSlots
_G.QueryGuildBankTab = orig16QueryGuildBankTab
print("[PASS] MoP/Classic Warbank fail-closed, bank offset, and Guild Bank gate tests passed.")

-- Test 17: Virtual Bank Tab Family Resolution, C_Bank.IsItemAllowedInBankType, and Character Bank CanUseBank
local orig17GetContainerNumFreeSlots = _G.C_Container.GetContainerNumFreeSlots
local orig17ContainerIDToInventoryID = _G.C_Container.ContainerIDToInventoryID
local orig17GetContainerNumSlots = _G.C_Container.GetContainerNumSlots
local orig17GetInventoryItemID = _G.GetInventoryItemID
local orig17GetItemFamily = Private.APIAdapter.GetItemFamily
local orig17CBank = _G.C_Bank
local orig17Enum = _G.Enum
local orig17ItemLocation = _G.ItemLocation
local orig17MockContainers = mockContainers

local invLookupCalls = 0
_G.C_Container.ContainerIDToInventoryID = function(bag)
    invLookupCalls = invLookupCalls + 1
    if bag == 5 then return 68 end
    return nil
end
_G.GetInventoryItemID = function(unit, slot)
    if unit == "player" and slot == 68 then
        return 44446
    end
    return nil
end
Private.APIAdapter.GetItemFamily = function(itemInput)
    if itemInput == 44446 then
        return 1024
    end
    return 0
end

-- 17a: GetBagItemFamily prefers C_Container.GetContainerNumFreeSlots without calling ContainerIDToInventoryID
_G.C_Container.GetContainerNumFreeSlots = function(bag)
    if bag == 5 then
        return 16, 2048
    end
    if bag >= 6 and bag <= 23 then
        return 98, 0
    end
    return 0, nil
end

invLookupCalls = 0
assert(Private.APIAdapter.GetBagItemFamily(6) == 0, "Test 17a: Retail CharacterBankTab 6 should resolve family 0")
assert(Private.APIAdapter.GetBagItemFamily(11) == 0, "Test 17a: Retail CharacterBankTab 11 should resolve family 0")
assert(Private.APIAdapter.GetBagItemFamily(12) == 0, "Test 17a: Retail AccountBankTab 12 should resolve family 0")
assert(Private.APIAdapter.GetBagItemFamily(14) == 0, "Test 17a: Forever CharacterBankTab 14 should resolve family 0")
assert(Private.APIAdapter.GetBagItemFamily(15) == 0, "Test 17a: Forever AccountBankTab 15 should resolve family 0")
assert(Private.APIAdapter.GetBagItemFamily(23) == 0, "Test 17a: Forever AccountBankTab 23 should resolve family 0")
assert(Private.APIAdapter.GetBagItemFamily(5) == 2048, "Test 17a: Reagent/specialty bag 5 should return bagFamily 2048")
assert(invLookupCalls == 0, "Test 17a: ContainerIDToInventoryID must not be called when GetContainerNumFreeSlots returns a family")

-- 17b: Virtual bank tab guard when GetContainerNumFreeSlots is absent or returns nil bagFamily
_G.Enum = {
    BagIndex = {
        CharacterBankTab_1 = 6,
        CharacterBankTab_2 = 7,
        CharacterBankTab_3 = 8,
        CharacterBankTab_4 = 9,
        CharacterBankTab_5 = 10,
        CharacterBankTab_6 = 11,
        AccountBankTab_1 = 12,
        AccountBankTab_2 = 13,
        AccountBankTab_3 = 14,
        AccountBankTab_4 = 15,
        AccountBankTab_5 = 16,
    }
}
_G.C_Bank = {
    FetchPurchasedBankTabIDs = function()
        return {}
    end
}
_G.C_Container.GetContainerNumFreeSlots = function()
    return 0, nil
end

invLookupCalls = 0
assert(Private.APIAdapter.GetBagItemFamily(6) == 0, "Test 17b: Retail tab 6 must return 0 when GetContainerNumFreeSlots returns nil")
assert(Private.APIAdapter.GetBagItemFamily(11) == 0, "Test 17b: Unpurchased Retail tab 11 must return 0 via Enum.BagIndex")
assert(Private.APIAdapter.GetBagItemFamily(12) == 0, "Test 17b: Retail Warbank tab 12 must return 0")
assert(invLookupCalls == 0, "Test 17b: ContainerIDToInventoryID must not be called on Retail virtual bank tabs")

_G.C_Container.GetContainerNumFreeSlots = nil
_G.Enum = {
    BagIndex = {
        CharacterBankTab_1 = 6,
        CharacterBankTab_2 = 7,
        CharacterBankTab_3 = 8,
        CharacterBankTab_4 = 9,
        CharacterBankTab_5 = 10,
        CharacterBankTab_6 = 11,
        CharacterBankTab_7 = 12,
        CharacterBankTab_8 = 13,
        CharacterBankTab_9 = 14,
        AccountBankTab_1 = 15,
        AccountBankTab_2 = 16,
        AccountBankTab_3 = 17,
        AccountBankTab_4 = 18,
        AccountBankTab_5 = 19,
        AccountBankTab_6 = 20,
        AccountBankTab_7 = 21,
        AccountBankTab_8 = 22,
        AccountBankTab_9 = 23,
    }
}
invLookupCalls = 0
assert(Private.APIAdapter.GetBagItemFamily(14) == 0, "Test 17b: Forever tab 14 must return 0 when GetContainerNumFreeSlots is nil")
assert(Private.APIAdapter.GetBagItemFamily(23) == 0, "Test 17b: Forever tab 23 must return 0 when GetContainerNumFreeSlots is nil")
assert(invLookupCalls == 0, "Test 17b: ContainerIDToInventoryID must not be called on Forever virtual bank tabs")

_G.Enum = nil
_G.C_Bank = {
    FetchPurchasedBankTabIDs = function(bankType)
        if bankType == 0 then return { 6, 7 } end
        if bankType == 2 then return { 12 } end
        return {}
    end
}
invLookupCalls = 0
assert(Private.APIAdapter.GetBagItemFamily(6) == 0, "Test 17b: FetchPurchasedBankTabIDs fallback must guard bank tab 6")
assert(Private.APIAdapter.GetBagItemFamily(12) == 0, "Test 17b: FetchPurchasedBankTabIDs fallback must guard warbank tab 12")
assert(invLookupCalls == 0, "Test 17b: ContainerIDToInventoryID must not be called for purchased bank tabs without Enum")

-- Classic / MoP legacy layout (no CharacterBankTab_1) must preserve ContainerIDToInventoryID fallback
_G.C_Bank = nil
_G.Enum = {
    BagIndex = {
        Bank = -1,
        BankBag_1 = 6,
        AccountBankTab_1 = 13,
    }
}
invLookupCalls = 0
assert(Private.APIAdapter.GetBagItemFamily(5) == 1024, "Test 17b: Classic physical bank bag 5 must preserve ContainerIDToInventoryID fallback")
assert(invLookupCalls == 1, "Test 17b: Classic physical bank bag 5 must invoke ContainerIDToInventoryID once")

-- 17c: C_Bank.IsItemAllowedInBankType filtering in BagToBank and BagToWarbank
_G.Enum = {
    BankType = { Character = 0, Guild = 1, Account = 2 },
    BagIndex = {
        CharacterBankTab_1 = 6,
        AccountBankTab_1 = 12,
    }
}
_G.ItemLocation = {
    CreateFromBagAndSlot = function(self, bag, slot)
        return { bag = bag, slot = slot }
    end
}
local canUseCharBank = true
_G.C_Bank = {
    CanUseBank = function(bankType)
        if bankType == 0 then return canUseCharBank end
        return true
    end,
    FetchPurchasedBankTabIDs = function(bankType)
        if bankType == 0 then return { 6 } end
        if bankType == 2 then return { 12 } end
        return {}
    end,
    IsItemAllowedInBankType = function(bankType, itemLocation)
        if itemLocation and itemLocation.bag == 0 and itemLocation.slot == 1 then
            return false -- Soulbound / restricted item in slot 1
        end
        if itemLocation and itemLocation.bag == 0 and itemLocation.slot == 2 then
            return true -- Warbound / bankable item in slot 2
        end
        return true
    end
}
_G.C_Container.GetContainerNumSlots = function(bag)
    if bag == 0 or bag == 6 or bag == 12 then return 4 end
    return 0
end
mockContainers = {
    [0] = {
        [1] = { itemID = 12345, stackCount = 10, isLocked = false, isBound = true, hyperlink = "item:12345" },
        [2] = { itemID = 12345, stackCount = 10, isLocked = false, isBound = true, hyperlink = "item:12345" },
    },
    [6] = {},
    [12] = {},
}

local bankIterSlots = {}
for _, slotId in Private.BagToBank:SlotIterator("i:12345") do
    table.insert(bankIterSlots, slotId)
end
assert(#bankIterSlots == 1 and bankIterSlots[1] == lib.encode_bagslot(0, 2),
    "Test 17c: BagToBank:SlotIterator must skip disallowed slot (0,1) and yield allowed slot (0,2)")

local warbankIterSlots = {}
for _, slotId in Private.BagToWarbank:SlotIterator("i:12345") do
    table.insert(warbankIterSlots, slotId)
end
assert(#warbankIterSlots == 1 and warbankIterSlots[1] == lib.encode_bagslot(0, 2),
    "Test 17c: BagToWarbank:SlotIterator must skip disallowed slot (0,1) and allow Warbound isBound=true slot (0,2)")

local b2wTimeout = false
local b2wDone = false
lib:Move({ ["i:12345"] = 10 }, "BagToWarbank", function(event)
    if event == "TIMEOUT_ERROR" then b2wTimeout = true end
    if event == "DONE" then b2wDone = true end
end)
ticks = 0
while frameShown and ticks < 30 do
    ticks = ticks + 1
    if frameScript then frameScript(nil, 0.05) end
end
assert(b2wDone == true and b2wTimeout == false, "Test 17c: BagToWarbank move must complete without TIMEOUT_ERROR")
assert(mockContainers[0][1].stackCount == 10, "Test 17c: Disallowed slot (0,1) must remain untouched")
assert(mockContainers[0][2].stackCount == 0, "Test 17c: Allowed Warbound slot (0,2) must be moved")
assert(mockContainers[12][1] and mockContainers[12][1].stackCount == 10, "Test 17c: Warbank tab 12 slot 1 must receive 10")

-- When only disallowed slot (0,1) remains, BagToBank must skip it cleanly with DONE and no TIMEOUT_ERROR
local b2bTimeout = false
local b2bDone = false
lib:Move({ ["i:12345"] = 10 }, "BagToBank", function(event)
    if event == "TIMEOUT_ERROR" then b2bTimeout = true end
    if event == "DONE" then b2bDone = true end
end)
ticks = 0
while frameShown and ticks < 30 do
    ticks = ticks + 1
    if frameScript then frameScript(nil, 0.05) end
end
assert(b2bDone == true and b2bTimeout == false, "Test 17c: BagToBank with only disallowed item must emit DONE without TIMEOUT_ERROR")
assert(mockContainers[0][1].stackCount == 10, "Test 17c: Disallowed slot (0,1) must remain untouched after BagToBank")

-- Missing ItemLocation global must safely fall back to allowing slots
_G.ItemLocation = nil
local fallbackIterCount = 0
for _ in Private.BagToBank:SlotIterator("i:12345") do
    fallbackIterCount = fallbackIterCount + 1
end
assert(fallbackIterCount == 1, "Test 17c: BagToBank:SlotIterator must safely fall back when ItemLocation is nil")

local fallbackWarbankCount = 0
for _ in Private.BagToWarbank:SlotIterator("i:12345") do
    fallbackWarbankCount = fallbackWarbankCount + 1
end
assert(fallbackWarbankCount == 1, "Test 17c: BagToWarbank:SlotIterator must safely fall back when ItemLocation is nil")

-- 17d: Character Bank HasPermission via C_Bank.CanUseBank
canUseCharBank = false
assert(Private.BagToBank:HasPermission() == false, "Test 17d: BagToBank:HasPermission must return false when CanUseBank(0) is false")
assert(Private.BankToBag:HasPermission() == false, "Test 17d: BankToBag:HasPermission must return false when CanUseBank(0) is false")

local b2bPermErr = false
local b2bPermDone = false
lib:Move({ ["i:12345"] = 1 }, "BagToBank", function(event)
    if event == "PERMISSION_ERROR" then b2bPermErr = true end
    if event == "DONE" then b2bPermDone = true end
end)
if frameScript then frameScript(nil, 0.05) end
assert(b2bPermErr == true and b2bPermDone == false and Private.Scheduler.active == false,
    "Test 17d: BagToBank must emit PERMISSION_ERROR, suppress DONE, and clear scheduler when CanUseBank(0) is false")

local bank2bPermErr = false
local bank2bPermDone = false
lib:Move({ ["i:12345"] = 1 }, "BankToBag", function(event)
    if event == "PERMISSION_ERROR" then bank2bPermErr = true end
    if event == "DONE" then bank2bPermDone = true end
end)
if frameScript then frameScript(nil, 0.05) end
assert(bank2bPermErr == true and bank2bPermDone == false and Private.Scheduler.active == false,
    "Test 17d: BankToBag must emit PERMISSION_ERROR, suppress DONE, and clear scheduler when CanUseBank(0) is false")

canUseCharBank = true
assert(Private.BagToBank:HasPermission() == true, "Test 17d: BagToBank:HasPermission must return true when CanUseBank(0) is true")
assert(Private.BankToBag:HasPermission() == true, "Test 17d: BankToBag:HasPermission must return true when CanUseBank(0) is true")

_G.C_Bank = nil
assert(Private.BagToBank:HasPermission() == true, "Test 17d: BagToBank:HasPermission must return true when C_Bank is nil")
assert(Private.BankToBag:HasPermission() == true, "Test 17d: BankToBag:HasPermission must return true when C_Bank is nil")

-- Restore Test 17 globals
_G.C_Container.GetContainerNumFreeSlots = orig17GetContainerNumFreeSlots
_G.C_Container.ContainerIDToInventoryID = orig17ContainerIDToInventoryID
_G.C_Container.GetContainerNumSlots = orig17GetContainerNumSlots
_G.GetInventoryItemID = orig17GetInventoryItemID
Private.APIAdapter.GetItemFamily = orig17GetItemFamily
_G.C_Bank = orig17CBank
_G.Enum = orig17Enum
_G.ItemLocation = orig17ItemLocation
mockContainers = orig17MockContainers
print("[PASS] Virtual bank tab family, IsItemAllowedInBankType, and Character Bank CanUseBank tests passed.")

print("=== ALL TESTS PASSED SUCCESSFULLY! ===")
