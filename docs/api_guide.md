# LibItemMove-1.0 Developer API Guide

`LibItemMove-1.0` is an asynchronous, cooperative item movement library for World of Warcraft addons. It enables non-blocking item transfers between player character bags, character bank, Guild Bank, and account Warbanks while respecting client/server latency, rate limits, specialty bag restrictions, and cursor safety.

---

## Table of Contents

1. [Embedding in Your Addon](#1-embedding-in-your-addon)
2. [Contexts Overview & Meanings](#2-contexts-overview--meanings)
3. [Packed SlotId Specification](#3-packed-slotid-specification)
4. [Callback System & Error Handling](#4-callback-system--error-handling)
5. [Code Examples for Typical Tasks](#5-code-examples-for-typical-tasks)
   - [Example A: Moving Items from Bags to Character Bank](#example-a-moving-items-from-bags-to-character-bank)
   - [Example B: Withdrawing Items from Character Bank to Bags](#example-b-withdrawing-items-from-character-bank-to-bags)
   - [Example C: Depositing Items into Guild Bank (Rate-Limited)](#example-c-depositing-items-into-guild-bank-rate-limited)
   - [Example D: Transferring Items to Account Warbank](#example-d-transferring-items-to-account-warbank)
   - [Example E: Global Event Subscriptions via CallbackHandler-1.0](#example-e-global-event-subscriptions-via-callbackhandler-10)

---

## 1. Embedding in Your Addon

### TOC Dependencies
Include `LibStub` and `LibItemMove-1.0` in your addon's `.toc` file (or embed them in your `libs/` folder):

```toc
## Interface: 11503, 40400, 110002
## Title: MyInventoryAddon
## OptionalDeps: LibStub, LibItemMove-1.0

libs\LibStub\LibStub.lua
libs\LibItemMove-1.0\libItemMove.toc
```

### Embedded Include Pattern (XML)
Alternatively, if your addon uses an XML layout file (e.g. `bindings.xml` or custom layout manifests) to load dependencies, you can load `LibItemMove-1.0` using a single `<Include>` tag. This is particularly useful when embedding the library directly in your addon's subdirectories:

```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/">
    <!-- Load LibItemMove-1.0 using the XML manifest -->
    <Include file="libs/LibItemMove-1.0/libItemMove.xml"/>
</Ui>
```

> [!NOTE]
> Make sure `LibStub` is loaded before including `libItemMove.xml` so the library can register itself correctly.

### Acquiring the Library Instance
Inside your Lua script, request the library from `LibStub`:

```lua
local LibItemMove = LibStub:GetLibrary("LibItemMove-1.0")
if not LibItemMove then return end
```

---

## 2. Contexts Overview & Meanings

Move operations require a `MoveContext` strategy object describing the transfer direction and container rules. You retrieve context strategies via `LibItemMove:GetContext(direction)`.

| Direction String | Context Class | Description / Constraints |
| :--- | :--- | :--- |
| `"BagToBank"` / `"bag_to_bank"` | `BagToBank` | Moves items from player Bags (`0..5`) to character Bank containers (`-1`, `6..12`). Consolidates partial stacks first. |
| `"BankToBag"` / `"bank_to_bag"` | `BankToBag` | Moves items from character Bank containers (`-1`, `6..12`) to player Bags (`0..5`). Consolidates partial stacks first. |
| `"BagToGuildBank"` / `"bag_to_guildbank"` | `BagToGuildBank` | Moves non-soulbound items from player Bags to Guild Bank (either single active tab, or multiple tabs sequentially). Checks deposit permissions and **enforces 1 move per yield cycle**. |
| `"GuildBankToBag"` / `"guildbank_to_bag"` | `GuildBankToBag` | Moves items from current Guild Bank tab to player Bags (`0..5`). Checks withdraw permissions and **enforces 1 move per yield cycle**. |
| `"BagToWarbank"` / `"bag_to_warbank"` | `BagToWarbank` | Moves items from player Bags to account Warbank tabs (`13..17`). Consolidates partial stacks first. |
| `"WarbankToBag"` / `"warbank_to_bag"` | `WarbankToBag` | Moves items from account Warbank tabs (`13..17`) to player Bags (`0..5`). Consolidates partial stacks first. |

---

## 3. Packed SlotId Specification

To eliminate table allocations during scanning, slots are packed into single integer identifiers:

$$\text{SlotId} = (\text{BagID} \times 1000) + \text{SlotIndex}$$

### Helper Utility Functions
```lua
-- Encode bag 1, slot 15 -> 1015
local slotId = LibItemMove.encode_bagslot(1, 15)

-- Decode -995 -> bag -1 (Bank), slot 5
local bag, slot = LibItemMove.decode_bagslot(-995)
```

> [!NOTE]
> WoW container IDs can be negative (e.g. `BANK_CONTAINER = -1`). `decode_bagslot` correctly restores negative bag indices.

---

## 4. Callback System & Error Handling

`LibItemMove-1.0` uses a **hybrid callback system**. You can provide an inline callback function when calling `Move()`, and/or register for global events via `CallbackHandler-1.0`.

### Event Types & Arguments

| Event Name | Signature | Description |
| :--- | :--- | :--- |
| `"PROGRESS"` | `(event, itemString, qtyMoved)` | Fired immediately after a single stack slot transfer is verified. |
| `"UPDATE_UI"` | `(event)` | Fired after one or more successful moves to signal UI redraw. |
| `"CURSOR_LOCKED_ERROR"` | `(event)` | Fired if `GetCursorInfo()` is non-nil at routine start (protects player's held cursor items). |
| `"PERMISSION_ERROR"` | `(event)` | Fired if the player lacks deposit or withdrawal permissions (e.g., Guild Bank tab access). |
| `"TIMEOUT_ERROR"` | `(event)` | Fired if a move transaction fails to verify within 2 seconds. Transferred cursor is cleaned via `ClearCursor()`. |
| `"DONE"` | `(event)` | Fired when all requested transfers in the queue have completed. |

---

## 5. Code Examples for Typical Tasks

### Example A: Moving Items from Bags to Character Bank

```lua
local LibItemMove = LibStub("LibItemMove-1.0")

-- Define item strings and quantities to deposit
local moveQueue = {
    ["i:12345"] = 20, -- Move up to 20 of Item 12345
    ["item:67890:0:0"] = 5 -- Move up to 5 of Item 67890
}

-- Execute transfer using direct callback
LibItemMove:Move(moveQueue, "BagToBank", function(event, item, qty)
    if event == "PROGRESS" then
        print(string.format("Moved %d of %s to Bank.", qty, item))
    elseif event == "UPDATE_UI" then
        MyAddonFrame:UpdateBagView()
    elseif event == "CURSOR_LOCKED_ERROR" then
        print("|cffff0000Please release your cursor item before moving items.|r")
    elseif event == "TIMEOUT_ERROR" then
        print("|cffff0000Item transfer timed out! Please try again.|r")
    elseif event == "DONE" then
        print("All bank deposits completed!")
    end
end)
```

### Example B: Withdrawing Items from Character Bank to Bags

```lua
local moveQueue = {
    ["i:12345"] = 10 -- Withdraw 10 items
}

LibItemMove:Move(moveQueue, "BankToBag", function(event, item, qty)
    if event == "DONE" then
        print("Withdrawal complete!")
    end
end)
```

### Example C: Depositing Items into Guild Bank (Rate-Limited)

```lua
local moveQueue = {
    ["i:20001"] = 100 -- Deposit 100 herbs into Guild Bank
}

-- Guild Bank moves check tab deposit permissions and execute 1 item per yield cycle
LibItemMove:Move(moveQueue, "BagToGuildBank", function(event, item, qty)
    if event == "PERMISSION_ERROR" then
        print("|cffff0000You do not have deposit permissions on this Guild Bank tab.|r")
    elseif event == "PROGRESS" then
        print("Guild Bank deposit progress:", item, qty)
    elseif event == "DONE" then
        print("Guild Bank deposit finished!")
    end
end)
```

### Example C.2: Sequential Multi-Tab Guild Bank Transfers

You can deposit items into multiple specific guild bank tabs by formatting the `moveQueue` as a tab-keyed dictionary containing nested item-quantity structures:

```lua
-- Define specific tabs and item lists
local multiTabQueue = {
    [2] = {
        ["i:20001"] = 20, -- Deposit 20 herbs to Tab 2
    },
    [3] = {
        ["i:20002"] = 10, -- Deposit 10 ore to Tab 3
    }
}

-- Execute multi-tab transfer
LibItemMove:Move(multiTabQueue, "BagToGuildBank", function(event, item, qty)
    if event == "PROGRESS" then
        print(string.format("Moved %d of %s to current tab.", qty, item))
    elseif event == "TIMEOUT_ERROR" then
        print("|cffff0000Tab switch or transfer timed out! Sequence aborted.|r")
    elseif event == "DONE" then
        print("All multi-tab transfers finished successfully!")
    end
end)
```

### Example D: Transferring Items to Account Warbank

```lua
local moveQueue = {
    ["i:30002"] = 50
}

LibItemMove:Move(moveQueue, "BagToWarbank", function(event, item, qty)
    if event == "DONE" then
        print("Warbank deposit finished!")
    end
end)
```

### Example E: Global Event Subscriptions via CallbackHandler-1.0

If your addon consists of multiple independent UI widgets, you can register global event listeners:

```lua
local MyWidget = {}

-- Register for global LibItemMove events
LibItemMove.RegisterCallback(MyWidget, "LibItemMove_PROGRESS", function(event, itemString, qtyMoved)
    print("Global Listener Progress:", itemString, qtyMoved)
end)

LibItemMove.RegisterCallback(MyWidget, "LibItemMove_DONE", function(event)
    print("Global Listener: All moves finished!")
end)

-- Initiate move (events will be broadcast to MyWidget)
LibItemMove:Move({ ["i:12345"] = 5 }, "BagToBank")
```
