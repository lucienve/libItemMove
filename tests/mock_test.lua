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

_G.CreateFrame = function(typeStr)
    return {
        Show = function(self) frameShown = true end,
        Hide = function(self) frameShown = false end,
        SetScript = function(self, event, fn)
            if event == "OnUpdate" then
                frameScript = fn
            end
        end
    }
end

-- Mock Container Data
local mockContainers = {
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
            cursorState = nil
            cursorItemId = nil
            local srcInfo = mockContainers[0][1]
            local movedQty = srcInfo.heldSplit or 15
            srcInfo.stackCount = srcInfo.stackCount - movedQty
            srcInfo.heldSplit = nil

            if not mockContainers[bag] then mockContainers[bag] = {} end
            mockContainers[bag][slot] = {
                itemID = 12345,
                stackCount = movedQty,
                isLocked = false,
                isBound = false,
                hyperLink = "item:12345"
            }
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

-- Test 2: Item ID Parsing & Strict Matching
local id1 = Private.Utils.GetItemIdFromString("i:12345")
local id2 = Private.Utils.GetItemIdFromString("item:12345:0:0")
assert(id1 == 12345 and id2 == 12345, "GetItemIdFromString failed")

local match1 = Private.Utils.IsItemMatching("item:12345:100:0", { itemID = 12345, itemLink = "item:12345:100:0" })
local match2 = Private.Utils.IsItemMatching("item:12345:200:0", { itemID = 12345, itemLink = "item:12345:100:0" })
assert(match1 == true and match2 == false, "Strict item link variant matching failed")
print("[PASS] Item ID Parsing & Strict Matching test passed.")

-- Test 3: Specialty Bag Family Compatibility
assert(Private.Utils.IsFamilyCompatible(4, 0) == true, "General bag compatibility failed")
assert(Private.Utils.IsFamilyCompatible(4, 4) == true, "Herb bag matching failed")
assert(Private.Utils.IsFamilyCompatible(4, 8) == false, "Mining vs Herb mismatch failed")
print("[PASS] Item Family Compatibility test passed.")

-- Test 4: Cursor Hold Early Abort Check
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

-- Test 5: Asynchronous Cooperative Move Execution & Stack Verification
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

print("=== ALL TESTS PASSED SUCCESSFULLY! ===")
