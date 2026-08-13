---@meta

--- Packed integer representing a bag slot: (bagID * 1000) + slotIndex
---@alias SlotId number

--- Event names passed to callbacks: "PROGRESS" | "UPDATE_UI" | "TIMEOUT_ERROR" | "CURSOR_LOCKED_ERROR" | "PERMISSION_ERROR" | "DONE"
---@alias CallbackEvent string

--- Table describing an individual slot movement transaction
---@class MoveData
---@field target SlotId Packed destination slot ID
---@field qty number Quantity to move
---@field endQty number Expected source slot quantity remaining after move
---@field item string Item string identifier (e.g. "i:12345")
---@field isPartial boolean True if merging into an existing partial stack

--- Map of item identifiers to quantity to move: { [itemString]: quantity }
---@alias MoveQueue table<string, number>

--- Abstract strategy interface for container movement directions
---@class MoveContext
---@field isGuildBank boolean Whether this context operates on a Guild Bank (enforces 1 move per yield cycle)
---@field isWarbank boolean Whether this context operates on a Warbank
---@field MoveSlot fun(self: MoveContext, fromSlotId: SlotId, toSlotId: SlotId, quantity: number) Splits item onto cursor and drops onto target slot
---@field GetSlotQuantity fun(self: MoveContext, slotId: SlotId): number Returns item stack count at slotId (0 if empty)
---@field GetSourceSlotQuantity fun(self: MoveContext, slotId: SlotId): number Returns item stack count at source slotId
---@field GetTargetSlotQuantity fun(self: MoveContext, slotId: SlotId): number Returns item stack count at target slotId
---@field GetSlotItemId fun(self: MoveContext, bag: number, slot: number): number? Returns item ID at bag & slot
---@field GetSourceSlotItemId fun(self: MoveContext, bag: number, slot: number): number? Returns item ID at source bag & slot
---@field GetTargetSlotItemId fun(self: MoveContext, bag: number, slot: number): number? Returns item ID at target bag & slot
---@field GetItemIdFromString fun(self: MoveContext, itemString: string|number): number? Parses numeric item ID from item string
---@field PickupItem fun(self: MoveContext, bag: number, slot: number) Drops held item or picks up item at slot
---@field GetEmptySlots fun(self: MoveContext, emptySlotIdsTable: SlotId[]) Appends eligible empty slot IDs sorted by family
---@field GetPartialSlots fun(self: MoveContext, itemString: string|number, partialSlotsTable: table[]) Appends eligible partial slot data { slotId, currentQty, roomLeft }
---@field SlotIterator fun(self: MoveContext, itemString: string|number): fun(): number?, SlotId?, number? Iterates source slots containing item
---@field SlotIdIterator fun(self: MoveContext, itemString: string|number): fun(): number?, SlotId?, number? Alias for SlotIterator
---@field IsSlotLocked fun(self: MoveContext, bag: number, slot: number): boolean Returns true if item is locked in transit
---@field IsSourceSlotLocked fun(self: MoveContext, bag: number, slot: number): boolean Returns true if source item is locked in transit
---@field IsTargetSlotLocked fun(self: MoveContext, bag: number, slot: number): boolean Returns true if target item is locked in transit
---@field HasPermission fun(self: MoveContext): boolean Returns true if player has permissions to perform moves in this context

---@class BaseContext : MoveContext
---@field New fun(self: BaseContext, o?: table): any Creates a new context instance
---@field ScanEmptySlots fun(self: BaseContext, containers: number[], emptySlotIdsTable: SlotId[]) Scans containers for empty slots
---@field ScanPartialSlots fun(self: BaseContext, containers: number[], itemString: string|number, partialSlotsTable: table[]) Scans containers for partial stacks
---@field ScanSourceSlots fun(self: BaseContext, containers: number[], itemString: string|number): fun(): number?, SlotId?, number? Scans containers for source item slots

--- Signature for per-move progress callbacks
---@alias MoveCallbackFun fun(event: CallbackEvent, ...: any)

--- Primary library interface table registered with LibStub
---@class LibItemMove
---@field callbacks table? CallbackHandler instance
---@field encode_bagslot fun(bag: number, slot: number): SlotId
---@field decode_bagslot fun(slotId: SlotId): number, number
---@field Move fun(self: LibItemMove, moveQueue: MoveQueue, context: MoveContext|string, callback?: MoveCallbackFun)
---@field GetContext fun(self: LibItemMove, direction: string): MoveContext
---@field RegisterCallback fun(self: LibItemMove, event: string, method?: string|function, ...: any)
---@field UnregisterCallback fun(self: LibItemMove, event: string)
---@field UnregisterAllCallbacks fun(self: LibItemMove)
---@field Debug boolean? Whether debug logs are enabled

--- Private internal namespace shared across addon files
---@class LibItemMovePrivate
---@field Utils table Utility functions module
---@field APIAdapter table Cross-version WoW API adapter module
---@field Scheduler table Coroutine scheduler module
---@field BaseContext BaseContext Base context strategy class
---@field BagToBank BaseContext Strategy for Bag -> Bank
---@field BankToBag BaseContext Strategy for Bank -> Bag
---@field BagToGuildBank BaseContext Strategy for Bag -> Guild Bank
---@field GuildBankToBag BaseContext Strategy for Guild Bank -> Bag
---@field BagToWarbank BaseContext Strategy for Bag -> Warbank
---@field WarbankToBag BaseContext Strategy for Warbank -> Bag
---@field Mover table Core mover engine module
---@field DebugLog fun(fmt: string, ...: any) Internal debug log helper
