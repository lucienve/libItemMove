# LibItemMove-1.0

**LibItemMove-1.0** is an asynchronous, cooperative item movement library for World of Warcraft addons. 

It provides utility functions for non-blocking item transfers between character bags, character bank, Guild Bank, and account Warbanks while respecting client/server latency, rate limits, specialty bag restrictions, and cursor safety.

---

## Key Features

* **Non-Blocking Cooperative Execution**: Uses a coroutine scheduler backed by frame `OnUpdate` ticks to prevent frame drops or game client freezes during large stack moves.
* **Modern Packed `SlotId` Standard**: Encodes slots as single packed integers `(BagID * 1000) + SlotIndex` to prevent GC memory allocation spikes and slot collisions in modern 100+ slot containers.
* **Cross-Version API Adapter**: Tailored primarily for **Classic Era (1.15.x)** while supporting Cataclysm/Wrath Classic and modern **Retail (11.x `C_Container`)**.
* **Specialty Bag Prioritization**: Automatically sorts empty destination slots, placing items into specialty bags (Herb, Mining, Reagent bags) before general bags.
* **Guild Bank Rate-Limit Throttling**: Limits Guild Bank transfers to 1 move per yield cycle to avoid server packet drops.
* **Transaction Verification & Lock Recovery**: Verifies source quantity reduction and destination item ID matching with a 2-second timeout window and 10-retry stuck cursor recovery.
* **Hybrid Callback System**: Supports per-transaction functional callbacks and Ace3 `CallbackHandler-1.0` event bus subscriptions.
* **Diagnostic Debug Mode**: Exposes a `Debug` property on the library to print real-time traces of slot prioritization, bag family mapping, and compatibility checks.

---

## Embedding in Your Addon

Embed the library in your addon folder (e.g. `libs/LibItemMove-1.0`) and load it using one of the following methods:

### Method A: TOC Reference
Reference the library's `.toc` manifest in your addon's `.toc` file:
```toc
libs\LibItemMove-1.0\libItemMove.toc
```

### Method B: XML Include (Embedded Include Pattern)
Include the library's XML manifest in your addon's XML layout file:
```xml
<Include file="libs/LibItemMove-1.0/libItemMove.xml"/>
```

---

## Quick Start Example

```lua
-- 1. Embed LibItemMove-1.0 via LibStub
local LibItemMove = LibStub("LibItemMove-1.0")

-- 2. Define items to move: { [itemString] = quantity }
local moveQueue = {
    ["i:12345"] = 20 -- Move up to 20 of Item 12345
}

-- 3. Execute transfer asynchronously
LibItemMove:Move(moveQueue, "BagToBank", function(event, item, qty)
    if event == "PROGRESS" then
        print(string.format("Moved %d of %s to Bank.", qty, item))
    elseif event == "UPDATE_UI" then
        MyAddonFrame:UpdateBagView()
    elseif event == "TIMEOUT_ERROR" then
        print("|cffff0000Item move timed out! Cursor cleaned.|r")
    elseif event == "DONE" then
        print("All transfers completed!")
    end
end)
```

---

## Available Movement Contexts

| Direction String | Description |
| :--- | :--- |
| `"BagToBank"` | Player Bags $\rightarrow$ Character Bank containers |
| `"BankToBag"` | Character Bank containers $\rightarrow$ Player Bags |
| `"BagToGuildBank"` | Player Bags $\rightarrow$ Guild Bank (Rate-limited, non-soulbound) |
| `"GuildBankToBag"` | Guild Bank $\rightarrow$ Player Bags (Rate-limited) |
| `"BagToWarbank"` | Player Bags $\rightarrow$ Account Warbank tabs |
| `"WarbankToBag"` | Account Warbank tabs $\rightarrow$ Player Bags |

---

## Documentation

For full documentation on context initialization, packed slot math, error recovery, and advanced `CallbackHandler-1.0` usage, see the [Developer API Guide](docs/api_guide.md).

---

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) for details.
