-- SpawnCamp vendor auto-buy: when the Talk key opens a vendor window, buy the
-- item picked in the Talk options. Made for limited-stock items (Pratt
-- McGrubben's Pattern: Turtle Scale Gloves): camp the vendor, press the key,
-- and the pattern is bought the moment it's in stock.
--
-- Only a window the Talk key opened (or a Talk target's own window) is
-- handled, the same rule as auto-chat and quests. Hold Shift to shop yourself.
--
-- The item list in the picker comes from two places:
--   * the vendor window that's open right now, if there is one;
--   * Questie's item database, which records who sells each item.

local ADDON, SC = ...

------------------------------------------------------------------------------
-- The open vendor window
------------------------------------------------------------------------------

-- name, price, sold in bundles of, in stock (-1 = unlimited), costs something
-- other than money
local function Slot(i)
    if GetMerchantItemInfo then
        local ok, name, _, price, batch, avail, _, _, extended = pcall(GetMerchantItemInfo, i)
        if ok and type(name) == "string" then return name, price or 0, batch or 1, avail or -1, extended and true or false end
    end
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
        if ok and type(info) == "table" and type(info.name) == "string" then
            return info.name, info.price or 0, info.stackCount or 1, info.numAvailable or -1, info.hasExtendedCost and true or false
        end
    end
end

local function SlotID(i)
    if GetMerchantItemID then
        local ok, id = pcall(GetMerchantItemID, i)
        if ok and type(id) == "number" then return id end
    end
end

local function NumSlots()
    return (GetMerchantNumItems and GetMerchantNumItems()) or 0
end

-- The slot selling the picked item: by item id when both sides have one,
-- else by name. Second result: every slot's name was readable.
local function Find(I)
    local want, wantID, loaded = (I.buy or ""):lower(), tonumber(I.buyID) or 0, true
    for i = 1, NumSlots() do
        local name = Slot(i)
        if not name then
            loaded = false
        elseif (wantID > 0 and SlotID(i) == wantID) or name:lower() == want then
            return i, true
        end
    end
    return nil, loaded
end

-- How many of slot i to buy: the amount set, or everything in stock for a
-- limited item (one, for an item that never runs out). Returns purchases
-- (bundles), or 0 and why not.
local function HowMany(I, i)
    local _, price, batch, avail, extended = Slot(i)
    if avail == 0 then return 0, "out" end
    local want = tonumber(I.buyCount) or 0
    local purchases
    if want > 0 then
        purchases = math.ceil(want / math.max(1, batch))
    else
        purchases = avail > 0 and avail or 1
    end
    if avail > 0 then purchases = math.min(purchases, avail) end
    if not extended and price > 0 then
        local can = math.floor((GetMoney and GetMoney() or 0) / price)
        if can <= 0 then return 0, "money" end
        purchases = math.min(purchases, can)
    end
    return purchases
end

local visit = { done = false, said = {} }

local function Say(key, text)
    if visit.said[key] then return end
    visit.said[key] = true
    SC.Print(text)
end

local function TryBuy()
    if visit.done or not SC.char then return end
    if not (MerchantFrame and MerchantFrame:IsShown()) and not visit.open then return end
    local I = SC.TalkWindow and SC.TalkWindow()
    if not I or (I.buy or "") == "" then return end
    local i, loaded = Find(I)
    if not i then
        -- Names still loading: MERCHANT_UPDATE or the retry comes back to it.
        if loaded and NumSlots() > 0 then
            Say("none", "|cffffffff" .. I.buy .. "|r isn't sold here.")
            visit.done = true
        end
        return
    end
    local name, _, batch = Slot(i)
    local n, why = HowMany(I, i)
    visit.done = true
    if n <= 0 then
        if why == "out" then
            Say("out", "|cffffffff" .. name .. "|r is out of stock.")
        else
            Say("money", "not enough money for |cffffffff" .. name .. "|r.")
        end
        return
    end
    if not BuyMerchantItem then return end
    if batch > 1 then
        for _ = 1, n do BuyMerchantItem(i) end
    else
        local stack = math.max(1, GetMerchantItemMaxStack and GetMerchantItemMaxStack(i) or 1)
        local left = n
        while left > 0 do
            local k = math.min(left, stack)
            BuyMerchantItem(i, k)
            left = left - k
        end
    end
    local what = (n * batch > 1 and (n * batch .. " x ") or "") .. name
    if SC.Alert then SC.Alert("Bought " .. what .. "!") else SC.Print("bought " .. what .. ".") end
end
SC.TryBuy = TryBuy

SC.On("MERCHANT_SHOW", function()
    visit = { done = false, said = {}, open = true }
    TryBuy()
    -- Item names can arrive a moment after the window does.
    for _, t in ipairs({ 0.3, 1 }) do
        C_Timer.After(t, function() if visit.open then pcall(TryBuy) end end)
    end
end)
SC.On("MERCHANT_UPDATE", function() if visit.open then TryBuy() end end)
SC.On("MERCHANT_CLOSED", function() visit.open = false end)

-- A vendor who chats first: the chat option that opens the shop.
function SC.VendorOption(options)
    local I = SC.char and SC.char.interact
    if not I or (I.buy or "") == "" then return nil end
    for _, opt in ipairs(options or {}) do
        local text = (SC.Plain and SC.Plain(opt.name) or opt.name or ""):lower()
        if opt.icon == 132060 or text:find("browse", 1, true) or text:find("your goods", 1, true)
            or text:find("buy from", 1, true) or text:find("for sale", 1, true) then
            return opt
        end
    end
end

------------------------------------------------------------------------------
-- The picker's list
------------------------------------------------------------------------------

local list, scanning      -- Questie's vendor items, once read

local function Faction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return type(f) == "string" and f:sub(1, 1) or nil
end

-- Reads every item Questie has a vendor for. step yields so it never stalls
-- a frame.
local function Collect(db, step)
    local byName, me, n = {}, Faction(), 0
    local function Q(fn, id, k)
        local ok, v = pcall(fn, id, k)
        if ok then return v end
    end
    for id in pairs(db.ItemPointers or {}) do
        n = n + 1
        if step and n % 300 == 0 then step() end
        local vendors = Q(db.QueryItemSingle, id, "vendors")
        if type(vendors) == "table" and next(vendors) then
            local name = Q(db.QueryItemSingle, id, "name")
            if type(name) == "string" and name ~= "" then
                -- Vendors of your faction (or neutral), by name. The same
                -- item name can be several item ids: one line, the lowest id.
                local e = byName[name]
                for _, npc in pairs(vendors) do
                    local side = Q(db.QueryNPCSingle, npc, "friendlyToFaction")
                    if not me or side == nil or side == 0 or (type(side) == "string" and side:find(me, 1, true)) then
                        local vn = Q(db.QueryNPCSingle, npc, "name")
                        if type(vn) == "string" and vn ~= "" then
                            if not e then
                                e = { id = id, who = {}, seen = {} }
                                byName[name] = e
                            end
                            if not e.seen[vn] then
                                e.seen[vn] = true
                                e.who[#e.who + 1] = vn
                            end
                        end
                    end
                end
                if e and id < e.id then e.id = id end
            end
        end
    end
    local out = {}
    for name, e in pairs(byName) do
        table.sort(e.who)
        out[#out + 1] = { text = name, id = e.id, value = name,
            sub = e.who[1] .. (#e.who > 1 and (" +" .. (#e.who - 1)) or ""),
            find = table.concat(e.who, " "):lower() }
    end
    table.sort(out, function(a, b) return a.text < b.text end)
    return out
end
SC._vendor = { Collect = Collect }

local function Scan()
    if list or scanning then return end
    local db = SC.QuestieDBs and SC.QuestieDBs()
    if not (db and db.ItemPointers and db.QueryItemSingle) then return end
    scanning = true
    local co = coroutine.create(function() list = Collect(db, coroutine.yield) end)
    local function Resume()
        local ok = coroutine.resume(co)
        if not ok then scanning = false; list = {}; return end
        if coroutine.status(co) == "dead" then
            scanning = false
            if SC.RefreshChooser then SC.RefreshChooser() end
        else
            C_Timer.After(0, Resume)
        end
    end
    Resume()
end

-- Lines for the chooser: None, what the open vendor sells, then every
-- vendor item Questie knows.
function SC.VendorItems()
    local I = SC.char.interact
    local picked = (I.buy or ""):lower()
    local out = { { text = "None", sub = "buy nothing", noIcon = true, value = "", id = 0, selected = picked == "" } }
    local here = {}
    if visit.open then
        for i = 1, NumSlots() do
            local name, _, _, avail = Slot(i)
            if name and not here[name] then
                here[name] = true
                local stock = avail == 0 and "sold here, out of stock" or (avail > 0 and ("sold here, " .. avail .. " in stock") or "sold here")
                out[#out + 1] = { text = name, sub = stock, id = SlotID(i) or 0, value = name, selected = name:lower() == picked }
            end
        end
    end
    Scan()
    if list then
        for _, it in ipairs(list) do
            if not here[it.text] then
                it.selected = it.text:lower() == picked
                out[#out + 1] = it
            end
        end
    elseif scanning then
        out[#out + 1] = { text = "Reading Questie's vendor list...", noIcon = true, value = nil }
    elseif not visit.open then
        out[#out + 1] = { text = "Open a vendor to list what they sell.", sub = "", noIcon = true, value = nil }
    end
    return out
end

function SC.ItemIcon(id)
    if not id or id == 0 then return nil end
    if C_Item and C_Item.GetItemIconByID then
        local ok, tex = pcall(C_Item.GetItemIconByID, id)
        if ok and tex then return tex end
    end
    if GetItemIcon then
        local ok, tex = pcall(GetItemIcon, id)
        if ok and tex then return tex end
    end
end
