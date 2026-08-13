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
        Fire = function(self, event, ...)
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
_G.GetCursorInfo = function()
    return cursorState, cursorItemId
end

_G.ClearCursor = function()
    cursorState = nil
    cursorItemId = nil
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
    if mockGuildBank[tab] and mockGuildBank[tab][slot] then
        local info = mockGuildBank[tab][slot]
        cursorState = "item"
        cursorItemId = info.itemID
        info.heldSplit = count
    end
end

_G.PickupGuildBankItem = function(tab, slot)
    if cursorState == "item" then
        local srcInfo = mockContainers[0][1]
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
    end
end


-- Mock Container Data
mockContainers = {
    [0] = { -- Player Bag 0
        [1] = { itemID = 12345, stackCount = 20, isLocked = false, isBound = false, hyperLink = "item:12345" }
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
        local info = mockContainers[bag][slot]
        if info then
            cursorState = "item"
            cursorItemId = info.itemID
            info.heldSplit = count
        end
    end,
    PickupContainerItem = function(bag, slot)
        if cursorState == "item" then
            local srcInfo = mockContainers[0][1]
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
                    hyperLink = "item:" .. id
                }
            end

            cursorState = nil
            cursorItemId = nil
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

-- Test 3: Robust Single-Table Return Protection for GetContainerItemInfo
local rawSingleTableHook = function(bag, slot)
    return { itemID = 555, stackCount = 10, isBound = true, hyperLink = "item:555" }
end

_G.GetContainerItemInfo = rawSingleTableHook
local tmpCContainer = _G.C_Container
_G.C_Container = nil -- Simulate legacy environment with overridden GetContainerItemInfo

local infoSingle = Private.APIAdapter.GetContainerItemInfo(1, 1)
assert(infoSingle ~= nil and infoSingle.itemID == 555 and infoSingle.isBound == true, "Single-table fallback hook protection failed!")
_G.C_Container = tmpCContainer
_G.GetContainerItemInfo = nil
print("[PASS] Single-table return protection test passed.")

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
mockContainers[0][1] = { itemID = 12345, stackCount = 20, isLocked = false, isBound = false, hyperLink = "item:12345" }
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
local ticks = 0
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
    [1] = { itemID = 888, stackCount = 20, isLocked = false, isBound = false, hyperLink = "item:888" }
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

local ticks = 0
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

print("=== ALL TESTS PASSED SUCCESSFULLY! ===")
