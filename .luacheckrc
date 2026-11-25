std = "lua51"

globals = {
    "C_Container",
    "C_Item",
    "C_Bank",
    "C_GuildBank",
    "Enum",
    "bit",
    "DEFAULT_CHAT_FRAME",
    "NUM_BAG_SLOTS",
    "NUM_BANKBAGSLOTS",
    "ITEM_INVENTORY_BANK_BAG_OFFSET",
    "NUM_REAGENTBAG_SLOTS",
    "REAGENTBAG_CONTAINER",
    "REAGENTBANK_CONTAINER",
    "GetContainerNumSlots",
    "GetContainerItemInfo",
    "GetContainerItemID",
    "GetItemInfo",
    "SplitContainerItem",
    "PickupContainerItem",
    "GetItemFamily",
    "ContainerIDToInventoryID",
    "GetInventoryItemID",
    "GetInventoryItemLink",
    "IsReagentBankUnlocked",
    "GetGuildBankTabInfo",
    "GetCurrentGuildBankTab",
    "SetCurrentGuildBankTab",
    "QueryGuildBankTab",
}

unused_args = false
max_line_length = false

exclude_files = {
    "log/**",
    ".types/**",
}

ignore = {
    "211/_",
}
