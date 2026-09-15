std = "lua51"

globals = {
    "LibStub",
    "CreateFrame",
    "GetTime",
    "GetCursorInfo",
    "ClearCursor",
    "C_Container",
    "C_Item",
    "C_Bank",
    "Enum",
    "bit",
    "DEFAULT_CHAT_FRAME",
    "NUM_BAG_SLOTS",
    "NUM_BANKBAGSLOTS",
    "REAGENTBAG_CONTAINER",
    "REAGENTBANK_CONTAINER",
    "GetContainerNumSlots",
    "GetContainerItemInfo",
    "GetContainerItemID",
    "SplitContainerItem",
    "PickupContainerItem",
    "GetItemFamily",
    "ContainerIDToInventoryID",
    "GetInventoryItemID",
    "GetInventoryItemLink",
    "IsReagentBankUnlocked",
    "GetGuildBankTabInfo",
    "GetGuildBankItemInfo",
    "GetGuildBankItemLink",
    "GetCurrentGuildBankTab",
    "SetCurrentGuildBankTab",
    "QueryGuildBankTab",
    "SplitGuildBankItem",
    "PickupGuildBankItem",
}

unused_args = false
max_line_length = false

exclude_files = {
    "log/**",
    ".types/**",
}

ignore = {
    "211/ADDON_NAME",
    "211/_",
}
