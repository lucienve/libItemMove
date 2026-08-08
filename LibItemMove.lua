local MAJOR, MINOR = "LibItemMove-1.0", 1
local LibStub = _G.LibStub

if not LibStub then
    error(MAJOR .. " requires LibStub.")
end

local lib = LibStub:NewLibrary(MAJOR, MINOR) --[[@as LibItemMove]]
if not lib then
    return -- Newer or equal version already loaded
end

---@type string, LibItemMovePrivate
local ADDON_NAME, Private = ...
Private = Private or {}

local Utils = Private.Utils
local Mover = Private.Mover

-- Embed CallbackHandler-1.0 if available
local CallbackHandler = LibStub:GetLibrary("CallbackHandler-1.0", true)
if CallbackHandler then
    lib.callbacks = lib.callbacks or CallbackHandler:New(lib)
end

--- Dispatcher helper for CallbackHandler events
--- @param event CallbackEvent
--- @param ... any
local function DispatchGlobalEvent(event, ...)
    if lib.callbacks then
        local eventName = "LibItemMove_" .. event
        lib.callbacks:Fire(eventName, ...)
    end
end

--- Encodes bag index and slot index into a packed SlotId integer.
--- @param bag number Container ID
--- @param slot number Slot index within container
--- @return SlotId slotId Packed integer (bag * 1000 + slot)
function lib.encode_bagslot(bag, slot)
    return Utils.encode_bagslot(bag, slot)
end

--- Decodes a packed SlotId integer into constituent bag and slot numbers.
--- @param slotId SlotId Packed integer
--- @return number bag Container ID
--- @return number slot Slot index
function lib.decode_bagslot(slotId)
    return Utils.decode_bagslot(slotId)
end

--- Returns a MoveContext strategy instance for the specified direction string.
--- @param direction string "BagToBank" | "BankToBag" | "BagToGuildBank" | "GuildBankToBag" | "BagToWarbank" | "WarbankToBag"
--- @return MoveContext context Strategy instance
function lib:GetContext(direction)
    if not direction then
        error("LibItemMove:GetContext requires a direction string.")
    end

    local normalized = direction:lower():gsub("_", "")
    if normalized == "bagtobank" then
        return Private.BagToBank
    elseif normalized == "banktobag" then
        return Private.BankToBag
    elseif normalized == "bagtoguildbank" then
        return Private.BagToGuildBank
    elseif normalized == "guildbanktobag" then
        return Private.GuildBankToBag
    elseif normalized == "bagtowarbank" then
        return Private.BagToWarbank
    elseif normalized == "warbanktobag" then
        return Private.WarbankToBag
    else
        error("LibItemMove: Unknown context direction '" .. tostring(direction) .. "'")
    end
end

--- Initiates an asynchronous cooperative item movement transaction.
--- @param moveQueue MoveQueue Map of itemString to quantity
--- @param context MoveContext|string Move strategy context or direction string
--- @param callback MoveCallbackFun? Direct per-move callback function
function lib:Move(moveQueue, context, callback)
    if not moveQueue or type(moveQueue) ~= "table" then
        error("LibItemMove:Move requires a valid moveQueue table.")
    end

    local ctxObj = context
    if type(context) == "string" then
        ctxObj = self:GetContext(context)
    end

    if not ctxObj or type(ctxObj.MoveSlot) ~= "function" then
        error("LibItemMove:Move requires a valid MoveContext strategy.")
    end

    Mover.StartMove(moveQueue, ctxObj, callback, DispatchGlobalEvent)
end

return lib
