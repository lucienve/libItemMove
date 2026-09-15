# Project Context

`LibItemMove-1.0` is an asynchronous, cooperative item movement library for World of Warcraft addons. It enables non-blocking item transfers between player character bags, character bank, Guild Bank, and account Warbanks.

## Current State & Architecture
- **Cooperative Scheduler**: Drives coroutines using frame update (`OnUpdate`) ticks to execute item moves asynchronously without causing UI freezes.
- **Packed Slot IDs**: Optimizes memory and avoids GC spikes by representing container slots as single integers: `(BagID * 1000) + SlotIndex`.
- **API Adapter**: Standardizes compatibility between Classic (Vanilla/Wrath/Cataclysm) and Retail container APIs.
- **Context Strategies**: Strategy classes that encapsulate direction-specific business rules (such as stack consolidation and specialty bag placement).
- **Embedded Include Pattern**: A newly added XML manifest [libItemMove.xml](../libItemMove.xml) in the root directory that allows parent addons to include the library using a single `<Include>` tag.

## Documentation
- [Developer API Guide](api_guide.md): Developer guide for embedding, context configuration, callbacks, and examples.
- [Library Design](library_design.md): Deep-dive document explaining core abstractions, adapters, sorting algorithms, and rate-limiting.

## Completed Tasks
- Added `libItemMove.xml` for support of the "Embedded Include" pattern.
- Updated `docs/api_guide.md`, `docs/library_design.md`, and `README.md` to document the XML manifest usage and internal script loading order.
- Fixed an issue in container family resolution where bag family checks would fail due to client-side item link caching latency by using `GetInventoryItemID` as the primary lookup method.
- Introduced a diagnostic logging subsystem (`lib.Debug` and `Private.DebugLog`) to trace container family resolution, empty slot scanning, and item compatibility matching in real-time.
- Modernized TOC manifest [libItemMove.toc](../libItemMove.toc) interface numbers to 11509 (Classic Era), 40402 (Cataclysm), 50504 (MoP Classic), and 120007 (Retail).
- Normalized TOC path delimiters to forward slashes (`/`) and cleaned up standalone library references while preserving `OptionalDeps`.
- Corrected Warbank container IDs from `13..17` to `12..16` (`Enum.BagIndex.AccountBankTab_1..5`) and added dynamic `C_Bank.FetchPurchasedBankTabIDs` resolution in [bag_to_warbank.lua](../contexts/bag_to_warbank.lua) and [warbank_to_bag.lua](../contexts/warbank_to_bag.lua).
- Centralized `GetContainerNumSlots` into [api_adapter.lua](../core/api_adapter.lua) and modernized Retail character bank tab resolution (`6..11`).
- Enhanced static typing in [types.lua](../core/types.lua), restricted `.luarc.json` `diagnostics.globals` to `LibStub`, configured [.luacheckrc](../.luacheckrc), and expanded unit test coverage in [mock_test.lua](../tests/mock_test.lua).

