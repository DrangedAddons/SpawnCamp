-- SpawnCamp vendor auto-buy: when the Talk key opens a vendor window, buy the
-- items picked in the Talk options (up to four). Made for limited-stock items (Pratt
-- McGrubben's Pattern: Turtle Scale Gloves): camp the vendor, press the key,
-- and the pattern is bought the moment it's in stock.
--
-- Only a window the Talk key opened (or a Talk target's own window) is
-- handled, the same rule as auto-chat and quests. Hold Shift to shop yourself.
--
-- An open vendor window never shows a restock: the game sends the stock list
-- when the window opens and not again. So when the picked item is out of
-- stock the window is closed, and the next key press opens a fresh one. That
-- makes spamming the key enough to camp a limited item.
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

------------------------------------------------------------------------------
-- The buy list
------------------------------------------------------------------------------

-- Up to MAX_BUYS items, each { name, id, count, got }:
--   count  how many you want (0 = whatever is in stock, once)
--   got    how many have been bought so far
-- An item is finished once got reaches count (or after one purchase when
-- count is 0), and is skipped from then on. Without that, a restock of a
-- pattern you already bought would be bought again while you camp the next.
local MAX_BUYS = 4
SC.MAX_BUYS = MAX_BUYS

function SC.Buys()
    local I = SC.char and SC.char.interact
    if not I then return {} end
    if type(I.buys) ~= "table" then
        -- Before 0.59.0 there was one item, in buy / buyID / buyCount.
        I.buys = {}
        if type(I.buy) == "string" and I.buy ~= "" then
            I.buys[1] = { name = I.buy, id = tonumber(I.buyID) or 0, count = tonumber(I.buyCount) or 0, got = 0 }
        end
        I.buy, I.buyID, I.buyCount = "", 0, 0
    end
    return I.buys
end

-- A recipe this character already knows, when "Skip recipes I already
-- know" is on. b.known is set when a vendor's window showed it as known.
local function SkipKnown(b)
    local I = SC.char and SC.char.interact
    return b.known == true and I ~= nil and I.skipKnown ~= false
end

function SC.BuyPending(b)
    if SkipKnown(b) then return false end
    local count, got = tonumber(b.count) or 0, tonumber(b.got) or 0
    if count > 0 then return got < count end
    return got == 0
end

local function AnyPending()
    for _, b in ipairs(SC.Buys()) do
        if SC.BuyPending(b) then return true end
    end
    return false
end

-- Sets row slot's item (a new row when slot is past the end). An empty name
-- removes the row. Picking an item starts it afresh.
function SC.SetBuy(slot, name, id)
    local buys = SC.Buys()
    if type(name) ~= "string" or name == "" then
        if buys[slot] then table.remove(buys, slot) end
        return
    end
    for i, b in ipairs(buys) do
        if i ~= slot and b.name:lower() == name:lower() then return end   -- already on the list
    end
    local b = buys[slot]
    if not b then
        if #buys >= MAX_BUYS then return end
        b = { count = 0 }
        buys[#buys + 1] = b
    end
    b.name, b.id, b.got, b.known = name, tonumber(id) or 0, 0, nil
end

-- A new amount also starts the item afresh.
function SC.SetBuyCount(slot, n)
    local b = SC.Buys()[slot]
    if not b then return end
    n = math.max(0, math.floor(tonumber(n) or 0))
    if n == (tonumber(b.count) or 0) then return end
    b.count, b.got = n, 0
end

-- Slot i's tooltip says "Already known" (a recipe you've learned). true,
-- false, or nil when the tooltip has no lines yet (item still loading).
local scanTip
local function ReadKnown(i)
    local known = ITEM_SPELL_KNOWN
    if type(known) ~= "string" then return false end
    if type(C_TooltipInfo) == "table" and C_TooltipInfo.GetMerchantItem then
        local data = C_TooltipInfo.GetMerchantItem(i)
        if type(data) == "table" and type(data.lines) == "table" then
            if #data.lines == 0 then return nil end
            for _, l in ipairs(data.lines) do
                if SC.Plain(l.leftText) == known then return true end
            end
            return false
        end
    end
    scanTip = scanTip or CreateFrame("GameTooltip", "SpawnCampScanTip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetMerchantItem(i)
    local n = scanTip:NumLines()
    if type(n) ~= "number" or n == 0 then return nil end
    for k = 1, n do
        local fs = _G["SpawnCampScanTipTextLeft" .. k]
        if fs and SC.Plain(fs:GetText()) == known then return true end
    end
    return false
end

local function Known(i)
    local ok, r = pcall(ReadKnown, i)
    if not ok then return false end
    return r
end

-- The slot selling item b: by item id when both sides have one, else by
-- name. Second result: every slot's name was readable.
local function Find(b)
    local want, wantID, loaded = (b.name or ""):lower(), tonumber(b.id) or 0, true
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

-- How many of slot i to buy for item b with this much money: what's left of
-- the amount set, or everything in stock for a limited item (one, for an
-- item that never runs out). Returns purchases (bundles) and the price of
-- one, or 0 and why not.
local function HowMany(b, i, money)
    local _, price, batch, avail, extended = Slot(i)
    if avail == 0 then return 0, "out" end
    local want = (tonumber(b.count) or 0) - (tonumber(b.got) or 0)
    local purchases
    if (tonumber(b.count) or 0) > 0 then
        purchases = math.ceil(want / math.max(1, batch))
    else
        purchases = avail > 0 and avail or 1
    end
    local short = avail > 0 and purchases > avail
    if avail > 0 then purchases = math.min(purchases, avail) end
    if not extended and price > 0 then
        local can = math.floor(money / price)
        if can <= 0 then return 0, "money" end
        purchases = math.min(purchases, can)
    else
        price = 0
    end
    return purchases, short and "short" or nil, price
end

local visit = { done = false, said = {} }
local list, scanning      -- Questie's vendor items, once read
local Scan

-- Once per window, and not again for SAY_AGAIN seconds: the key reopens the
-- window on every press while you camp, and that would fill the chat.
local SAY_AGAIN = 60
local lastSaid = {}
local function Say(key, text)
    if visit.said[key] then return end
    visit.said[key] = true
    local now = GetTime()
    if lastSaid[key] and lastSaid[key].text == text and now - lastSaid[key].t < SAY_AGAIN then return end
    lastSaid[key] = { text = text, t = now }
    SC.Print(text)
end

------------------------------------------------------------------------------
-- Quiet mode
------------------------------------------------------------------------------

-- Camping a vendor means opening him over and over: his greeting ("What can
-- I do for you?") and the window's open and close sounds on every press.
-- While that goes on, the game's Sound Effects and Dialog channels are
-- switched off, and put back QUIET_FOR seconds after the last reopen. Music
-- and ambience aren't touched, and SpawnCamp's own alerts play on the Master
-- channel, so "Bought ...!" is still heard.
--
-- What the two settings were is kept in the saved variables, so a crash or
-- logout in the middle can't leave them off: they're put back at login.
local QUIET_FOR = 8
local QUIET_CVARS = { "Sound_EnableSFX", "Sound_EnableDialog" }
local quietUntil = 0

local function CVarGet(n)
    if type(C_CVar) == "table" and C_CVar.GetCVar then return C_CVar.GetCVar(n) end
    return GetCVar and GetCVar(n)
end

local function CVarSet(n, v)
    if type(C_CVar) == "table" and C_CVar.SetCVar then C_CVar.SetCVar(n, v) elseif SetCVar then SetCVar(n, v) end
end

function SC.Unquiet()
    local db = rawget(_G, "SpawnCampDB")
    local saved = type(db) == "table" and db.quiet
    if type(saved) ~= "table" then return end
    db.quiet = nil
    for _, n in ipairs(QUIET_CVARS) do
        if type(saved[n]) == "string" then pcall(CVarSet, n, saved[n]) end
    end
end

local function Quiet()
    local I = SC.char and SC.char.interact
    local db = rawget(_G, "SpawnCampDB")
    if not I or I.quiet == false or type(db) ~= "table" then return end
    quietUntil = GetTime() + QUIET_FOR
    if type(db.quiet) ~= "table" then
        local saved = {}
        for _, n in ipairs(QUIET_CVARS) do
            local ok, v = pcall(CVarGet, n)
            if ok and v ~= nil then
                saved[n] = tostring(v)
                pcall(CVarSet, n, "0")
            end
        end
        db.quiet = saved
        if not SC.quietTold then
            SC.quietTold = true
            SC.Print("vendor sounds are muted while you camp. They come back " .. QUIET_FOR .. " seconds after your last press.")
        end
    end
    C_Timer.After(QUIET_FOR + 0.1, function()
        if GetTime() >= quietUntil then SC.Unquiet() end
    end)
end
SC.Quiet = Quiet

SC.On("PLAYER_LOGIN", function() SC.Unquiet() end)
SC.On("PLAYER_LOGOUT", function() SC.Unquiet() end)

-- Closes the vendor window so the next key press opens a fresh one. A frame
-- later: this runs inside the event that is still opening the window.
local function CloseToRecheck()
    Quiet()
    local token = visit
    C_Timer.After(0, function()
        if visit == token and visit.open and CloseMerchant then pcall(CloseMerchant) end
    end)
end

-- Questie lists this vendor as a seller of the item. A sold-out limited
-- item can be missing from the window altogether; this tells that apart
-- from a vendor who never sells it.
local function SellsPicked(name)
    Scan()
    local who = SC.UnitNameSafe and SC.UnitNameSafe("npc")
    if not (list and type(who) == "string") then return false end
    local want = (name or ""):lower()
    for _, it in ipairs(list) do
        if it.text:lower() == want then return it.find:find(who:lower(), 1, true) ~= nil end
    end
    return false
end

local function Names(t)
    local out = {}
    for _, n in ipairs(t) do out[#out + 1] = "|cffffffff" .. n .. "|r" end
    return table.concat(out, ", ")
end

local function TryBuy()
    if visit.done or not SC.char then return end
    if not (MerchantFrame and MerchantFrame:IsShown()) and not visit.open then return end
    if not AnyPending() then return end
    local I = SC.TalkWindow and SC.TalkWindow()
    if not I then return end
    visit.tried = visit.tried or {}
    visit.spent = visit.spent or 0
    local waiting = false
    for _, b in ipairs(SC.Buys()) do
        -- One go per item per window: stock read back after a purchase is stale.
        if not visit.tried[b] and SC.BuyPending(b) then
            local i, loaded = Find(b)
            if not i then
                -- Names still loading: MERCHANT_UPDATE or the retry comes back to it.
                if loaded and NumSlots() > 0 then
                    visit.tried[b] = SellsPicked(b.name) and "out" or "none"
                else
                    waiting = true
                end
            else
                local name, _, batch = Slot(i)
                -- A recipe you already know: not bought, and not waited for.
                local known = false
                if I.skipKnown ~= false then
                    known = Known(i)
                    -- Tooltip not in yet: the retries come back, and the
                    -- last one buys rather than wait for ever.
                    if known == nil and not visit.last then waiting = true end
                end
                local money = (GetMoney and GetMoney() or 0) - visit.spent
                local n, why, price = 0, nil, 0
                if known == true then
                    b.known = true
                    visit.tried[b] = "known"
                    if SC.Refresh then SC.Refresh() end
                elseif known == nil and waiting then
                    n = 0
                else
                    n, why, price = HowMany(b, i, money)
                    visit.tried[b] = why or "bought"
                end
                if n > 0 and BuyMerchantItem then
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
                    visit.spent = visit.spent + n * (price or 0)
                    b.got = (tonumber(b.got) or 0) + n * batch
                    local what = (n * batch > 1 and (n * batch .. " x ") or "") .. name
                    if SC.Alert then SC.Alert("Bought " .. what .. "!") else SC.Print("bought " .. what .. ".") end
                    if SC.Refresh then SC.Refresh() end
                end
            end
        end
    end
    if waiting then return end
    visit.done = true
    -- Out of stock (or short of the amount wanted) and still wanted: the
    -- window has to be reopened to see a restock.
    local out, none, money, known = {}, {}, {}, {}
    for _, b in ipairs(SC.Buys()) do
        local r = visit.tried[b]
        if r == "known" then
            known[#known + 1] = b.name
        elseif r == "none" then
            none[#none + 1] = b.name
        elseif r == "money" then
            money[#money + 1] = b.name
        elseif (r == "out" or r == "short") and SC.BuyPending(b) then
            out[#out + 1] = b.name
        end
    end
    if #known > 0 then Say("known", "you already know " .. Names(known) .. ": not bought.") end
    if #none > 0 then Say("none", Names(none) .. (#none > 1 and " aren't" or " isn't") .. " sold here.") end
    if #money > 0 then Say("money", "not enough money for " .. Names(money) .. ".") end
    if #out > 0 then
        Say("out", Names(out) .. (#out > 1 and " are" or " is") .. " out of stock. Closing the vendor: press your key again to check.")
        CloseToRecheck()
    else
        -- Nothing left to wait for: the window stays open, sounds come back.
        SC.Unquiet()
    end
end
SC.TryBuy = TryBuy

SC.On("MERCHANT_SHOW", function()
    visit = { done = false, said = {}, open = true }
    TryBuy()
    -- Item names can arrive a moment after the window does.
    local token = visit
    for _, t in ipairs({ 0.3, 1 }) do
        C_Timer.After(t, function()
            if visit == token and visit.open then
                if t == 1 then visit.last = true end
                pcall(TryBuy)
            end
        end)
    end
end)
SC.On("MERCHANT_UPDATE", function() if visit.open then TryBuy() end end)
SC.On("MERCHANT_CLOSED", function() visit.open = false end)

-- A vendor who chats first: the chat option that opens the shop.
function SC.VendorOption(options)
    if not (SC.char and AnyPending()) then return nil end
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
SC._vendor = { Collect = Collect, SetList = function(l) list = l end }

function Scan()
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
-- vendor item Questie knows. Items already on the buy list are marked.
function SC.VendorItems()
    local on = {}
    for _, b in ipairs(SC.Buys()) do on[b.name:lower()] = true end
    local out = { { text = "None", sub = "take this item off the list", noIcon = true, value = "", id = 0 } }
    local here = {}
    if visit.open then
        for i = 1, NumSlots() do
            local name, _, _, avail = Slot(i)
            if name and not here[name] then
                here[name] = true
                local stock = avail == 0 and "sold here, out of stock" or (avail > 0 and ("sold here, " .. avail .. " in stock") or "sold here")
                out[#out + 1] = { text = name, sub = stock, id = SlotID(i) or 0, value = name, selected = on[name:lower()] or false }
            end
        end
    end
    Scan()
    if list then
        for _, it in ipairs(list) do
            if not here[it.text] then
                it.selected = on[it.text:lower()] or false
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
