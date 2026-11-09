-- The game hooks of the ammunition system.
--
-- This is the InsurgencySandstormStyleReload mod's hook code, rewired to the
-- inventory: the magazine supply is the inventory, the loose ammunition is
-- the inventory, and packing a magazine takes the rounds out of the loose
-- ammunition you carry.
--
--   * Tap R: the next magazine in the rig or the pockets is loaded.
--   * Hold R: the weapon is put away and the loose rounds are packed into
--     the magazines, one round at a time.
--   * An ammo pickup becomes loose ammunition in the inventory.
--   * An ammo bag fills the magazines at once.
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Ammo then return end

local Ammo = PDTI.Ammo

local dropped = {}      -- magazines that lie on the floor
local holster = nil     -- "refill" or "pickup": the weapon is put away
local hooks_installed = false

local function log(message)
    local line = "[PDTI AMMO] " .. tostring(message)
    if _G.log then _G.log(line) else print(line) end
end

local function L(id, fallback)
    local loc = managers and managers.localization
    if loc and loc.exists and loc:exists(id) then return loc:text(id) end
    return fallback
end

------------------------------------------------------------- wrap helper

local function wrap(class_name, fn_name, make)
    local cls = rawget(_G, class_name)
    local current = cls and cls[fn_name]
    if type(current) ~= "function" then return false end

    Ammo.hooks = Ammo.hooks or {}
    local key = class_name .. "." .. fn_name
    local entry = Ammo.hooks[key]

    if entry and current == entry.hook then return true end
    -- Our hook is further down (another part of the mod wrapped on top).
    if PDTI.HookHas(current, "ammo") then return true end

    entry = entry or {}
    Ammo.hooks[key] = entry

    local inner = make(current)

    local function finish(ok, ...)
        entry.busy = false
        if not ok then error((...), 0) end
        return ...
    end

    entry.hook = function(self, ...)
        if entry.busy then return current(self, ...) end
        entry.busy = true
        return finish(pcall(inner, self, ...))
    end

    PDTI.HookMark(entry.hook, current, "ammo")
    cls[fn_name] = entry.hook
    return true
end

------------------------------------------------------- the reload stages

-- Without NQR there are no reload stages, so the mod derives them from the
-- reload timer: the old magazine leaves the gun at 30% of the reload, the new
-- one is in at 75%.
local function stage_out()
    return 0.3
end

local function stage_in()
    return 0.75
end

local function mag_left(wep, keep_drops)
    local rounds = math.max(0, wep:get_ammo_remaining_in_clip() - Ammo.ChamberOf(wep))
    wep._issr_mag_left_rounds = rounds
    wep._issr_mag_installed = { rounds = 0 }
    if not keep_drops then wep._issr_drop_count = 0 end
    wep._issr_no_mag = true
    Ammo.MarkPanelDirty()
end

local function mag_entered(wep)
    wep._issr_no_mag = nil
    Ammo.MarkPanelDirty()
end

local function reload_interrupted(wep)
    wep._issr_in_reload = nil
    wep._issr_reload_dropped = nil

    if not wep._issr_mag_left_rounds and (wep._issr_drop_count or 0) < 1 then return end

    local drops = wep._issr_drop_count or 0
    wep._issr_drop_count = 0
    wep._issr_mag_left_rounds = nil
    Ammo.MarkPanelDirty()

    if drops >= 1 then
        wep._issr_no_mag = true
        wep._issr_mag_gone = true
        wep._issr_mag_installed = { rounds = 0 }
    else
        wep._issr_mag_installed = {
            rounds = math.max(0, wep:get_ammo_remaining_in_clip() - Ammo.ChamberOf(wep))
        }
        wep._issr_no_mag = nil
        wep._issr_mag_gone = nil
    end
end

local function reload_started(wep)
    wep._issr_in_reload = true
    wep._issr_reload_dropped = nil
    wep._issr_drop_count = 0
end

-- The old magazine leaves the gun. Without NQR the mod decides whether it
-- really hits the floor.
local function mag_out_drop(wep)
    if rawget(_G, "NQR") ~= nil or wep._issr_reload_dropped then return end
    if not wep.drop_magazine_object then return end
    pcall(wep.drop_magazine_object, wep)
end

-------------------------------------------------------------- the reload

-- Forgets the taps of a reload (it ended or was interrupted).
local function clear_taps(wep)
    wep._pdti_dump = nil
    wep._pdti_fast_mul = nil
    wep._pdti_taps = nil
    wep._pdti_tap_t = nil
    wep._pdti_tap_origin = nil
    wep._pdti_tap_base = nil
    wep._pdti_akimbo_mode = nil
end
Ammo.ClearTaps = clear_taps

-- Akimbo guns: two magazines, one per gun, each with its own rounds.
--   one tap     "both": both magazines are changed
--   two taps    "one":  only the emptier magazine is changed
--   three taps  "dump": both are changed and the old ones are dropped
local function akimbo_reload(self, orig, info, ...)
    local chamber = Ammo.ChamberOf(self)
    local clip = self:get_ammo_remaining_in_clip()
    local kept = math.max(0, math.min(chamber, clip))
    local drops = self._issr_drop_count or 0
    local gone = self._issr_mag_gone
    local mode = self._pdti_akimbo_mode or "both"
    local pair = Ammo.AkimboPair(self) or { 0, 0 }

    self._issr_drop_count = 0

    -- The magazines in the guns, the emptier first. A magazine that fell to
    -- the floor is not in a gun any more.
    local specs = info.typed and Ammo.PairViews(self) or {}
    local old = {}
    local empty = self._pdti_gun_empty or {}
    if drops < 1 and not gone then
        -- A gun whose magazine was taken out has none to return.
        for g = 1, 2 do
            if not empty[g] then old[#old + 1] = { rounds = pair[g], spec = specs[g] } end
        end
        table.sort(old, function(a, b) return a.rounds < b.rounds end)
    end

    -- How many new magazines go in and how many old ones may come out. Two
    -- taps with a gun that has no magazine: that gun gets one, the other
    -- keeps its own.
    local want, give_back
    if mode == "one" and #old == 2 then
        want, give_back = 1, 1
    elseif mode == "one" then
        want, give_back = 2 - #old, 0
    else
        want, give_back = 2, #old
    end

    -- The new magazines come out first, so the old ones can go where the
    -- new ones were.
    local new = {}
    for _ = 1, want do
        local mag = Ammo.TakeMagazine(self)
        if not mag then break end
        new[#new + 1] = mag
    end

    if #new == 0 then
        -- Nothing to load: the guns keep what they have.
        clear_taps(self)
        self._issr_mag_left_rounds = nil
        self._issr_no_mag = nil
        self._issr_in_reload = nil
        self._issr_reload_dropped = nil
        self:set_ammo_total(clip)
        local ret = orig(self, ...)
        Ammo.SyncTotal(self)
        Ammo.MarkPanelDirty()
        return ret
    end

    -- As many old magazines come out as new ones go in, the emptiest first.
    local stay = {}
    for i, mag in ipairs(old) do
        if i <= math.min(#new, give_back) then
            if mode == "dump" then
                log(string.format("akimbo fast reload: a magazine was dropped with %d round(s)", mag.rounds))
            else
                Ammo.ReturnMagazine(self, mag.rounds, mag.spec)
            end
        else
            stay[#stay + 1] = mag
        end
    end
    self._issr_mag_gone = nil
    clear_taps(self)

    local rounds, loaded = {}, {}
    for _, mag in ipairs(stay) do
        rounds[#rounds + 1] = mag.rounds
        loaded[#loaded + 1] = mag.spec
    end
    for _, mag in ipairs(new) do
        rounds[#rounds + 1] = mag.rounds or 0
        loaded[#loaded + 1] = { size = mag.size, bullet = mag.bullet, load = mag.load }
    end
    local now_empty = {}
    while #rounds < 2 do
        rounds[#rounds + 1] = 0
        loaded[#loaded + 1] = loaded[1]
        now_empty[#rounds] = true
    end
    self._pdti_gun_empty = now_empty

    self._issr_mag_left_rounds = nil
    self._issr_no_mag = nil
    if info.typed then
        -- Each gun takes its magazine's size and bullets before the game
        -- fills the clip.
        Ammo.SetLoaded(self, loaded[1], loaded[2])
        self._pdti_pair = { rounds[1], rounds[2] }
        Ammo.ApplyLoaded(self)
    end
    self:set_ammo_total(rounds[1] + rounds[2] + kept)

    local ret = orig(self, ...)

    self._pdti_pair = { rounds[1], rounds[2] }
    local now = Ammo.AkimboPair(self)
    self._issr_mag_installed = { rounds = now[1] + now[2] }

    Ammo.SyncTotal(self)
    self._issr_in_reload = nil
    self._issr_reload_dropped = nil
    Ammo.MarkPanelDirty()
    return ret
end

local function make_on_reload_hook(orig)
    local function hook(self, ...)
        if Ammo.SkipWeapon(self) then return orig(self, ...) end

        local info = Ammo.Identify(self)
        if not info then return orig(self, ...) end

        Ammo.EnsureSupply(self)

        -- Loaded round by round: the rounds come out of the loose ammunition.
        if info.loose_fed then
            Ammo.SyncTotal(self)
            local before = self:get_ammo_remaining_in_clip()
            local ret = orig(self, ...)
            local loaded = self:get_ammo_remaining_in_clip() - before
            if loaded > 0 then
                local taken = Ammo.ConsumeLooseKey(info.key, loaded)
                if taken < loaded then self:set_ammo_remaining_in_clip(before + taken) end
            end
            Ammo.SyncTotal(self)
            Ammo.MarkPanelDirty()
            return ret
        end

        -- The magazine leaves the weapon's slot; the slot shows the new one
        -- after the reload.
        Ammo.ClearGunItems(self)

        if info.akimbo then return akimbo_reload(self, orig, info, ...) end

        local chamber = Ammo.ChamberOf(self)
        local kept = math.max(0, math.min(chamber, self:get_ammo_remaining_in_clip()))
        local drops = self._issr_drop_count or 0
        local clip = self:get_ammo_remaining_in_clip()

        self._issr_drop_count = 0

        local gone = self._issr_mag_gone

        -- Nothing to load: the magazine that was in the gun stays in it.
        if not Ammo.NextMagazine(self) and drops < 1 and not gone then
            self._issr_mag_left_rounds = nil
            self._issr_no_mag = nil
            self._issr_in_reload = nil
            self._issr_reload_dropped = nil
            self:set_ammo_total(clip)
            local ret = orig(self, ...)
            Ammo.SyncTotal(self)
            Ammo.MarkPanelDirty()
            return ret
        end

        self._issr_mag_gone = nil

        local next_mag = nil
        if drops < 1 and not gone then
            local actual = self._issr_mag_left_rounds
            if actual == nil then actual = math.max(0, clip - chamber) end
            if self._pdti_dump then
                -- R tapped twice: the magazine is dropped with its rounds.
                log(string.format("fast reload: the magazine was dropped with %d round(s)", actual))
            elseif Ammo.MustSwap(self) then
                -- No free place: the old magazine goes where the new one was.
                next_mag = Ammo.SwapMagazine(self, actual)
            else
                -- The magazine that was in the gun goes back into the inventory.
                Ammo.ReturnMagazine(self, actual)
            end
        end
        clear_taps(self)

        self._issr_mag_left_rounds = nil

        -- The next magazine comes out of the rig or the pockets.
        next_mag = next_mag or Ammo.TakeMagazine(self)

        self._issr_mag_installed = next_mag or { rounds = 0 }
        self._issr_no_mag = nil

        -- An assault rifle or SMG takes the new magazine's size and bullets
        -- before the game fills the clip.
        if info.typed and next_mag then
            Ammo.SetLoaded(self, next_mag)
            Ammo.ApplyLoaded(self)
        end

        local installed = self._issr_mag_installed
        local total = (installed.rounds or 0) + kept

        self:set_ammo_total(total)

        local ret = orig(self, ...)

        installed.rounds = math.max(0, self:get_ammo_remaining_in_clip() - chamber)

        Ammo.SyncTotal(self)

        self._issr_in_reload = nil
        self._issr_reload_dropped = nil

        Ammo.MarkPanelDirty()

        return ret
    end

    return hook
end

local function make_drop_hook(orig)
    local function hook(self, ...)
        if Ammo.SkipWeapon(self) then return orig(self, ...) end

        -- Without NQR this mod decides whether a magazine is dropped: only
        -- during a reload, at most once per reload, and only as far as the
        -- drop mode allows.
        if rawget(_G, "NQR") == nil then
            if not self._issr_in_reload then return orig(self, ...) end
            if self._issr_reload_dropped then return end

            local mode = math.max(0, math.min(2, math.floor((Ammo.settings.drop_mode or 1) + 0.5)))
            local rounds = math.max(self:get_ammo_remaining_in_clip() - Ammo.ChamberOf(self), 0)

            if mode == 0 or (mode == 1 and rounds > 0) then return end

            self._issr_reload_dropped = true
        end

        local mags = managers.enemy and managers.enemy._magazines
        local before = mags and #mags or 0
        local ret = orig(self, ...)

        if mags then
            local rounds = math.max(self:get_ammo_remaining_in_clip() - Ammo.ChamberOf(self), 0)
            local info = Ammo.Identify(self)
            local loaded = info and info.typed and Ammo.LoadedSpec(self)

            if info then
                for i = before + 1, #mags do
                    local entry = mags[i]
                    local col_unit = entry[2]

                    if alive(col_unit) then
                        col_unit:set_scale(Vector3(3, 3, 3))

                        dropped[col_unit:key()] = {
                            key = col_unit:key(),
                            col = col_unit,
                            mag = entry[1],
                            rounds = rounds,
                            queue_key = info.key,
                            pid = info.pid,
                            caliber = info.caliber,
                            akimbo = info.akimbo,
                            name_id = self._name_id,
                            typed = info.typed,
                            base_capacity = info.capacity,
                            size = loaded and loaded.size,
                            bullet = loaded and loaded.bullet,
                            load = loaded and Ammo.LoadString(loaded.load) or nil
                        }

                        self._issr_drop_count = (self._issr_drop_count or 0) + 1
                        Ammo.MarkPanelDirty()
                    end
                end
            end
        end

        return ret
    end

    return hook
end

local function make_stage_hook(orig)
    return function(self, t)
        local ret = orig(self, t)

        if not Ammo.settings.enabled or Ammo.SkipWeapon(self) then return ret end

        local cycle = self.r_cycle
        local stage = self.r_stage
        local name = cycle and stage and cycle[stage] or nil

        if name ~= self._issr_stage then
            self._issr_stage = name

            if name == "r_mag_out" then
                mag_left(self)
            elseif name == "r_get_new_mag_in" then
                mag_entered(self)
            end
        end

        return ret
    end
end

local function make_can_reload_hook(orig)
    return function(self, ...)
        if Ammo.settings.enabled and not Ammo.SkipWeapon(self) then
            Ammo.SyncTotal(self)
            -- A magazine weapon reloads only when there is a magazine with
            -- rounds in the rig or the pockets.
            if not Ammo.IsLooseFed(self) and not Ammo.NextMagazine(self) then
                return false
            end
        end
        return orig(self, ...)
    end
end

-- A shotgun loads shell by shell: every shell comes out of the loose rounds.
local function make_update_reloading_hook(orig)
    return function(self, t, dt, time_left)
        if not Ammo.settings.enabled or Ammo.SkipWeapon(self) or not Ammo.IsLooseFed(self) then
            return orig(self, t, dt, time_left)
        end
        local info = Ammo.Identify(self)
        local before = self:get_ammo_remaining_in_clip()
        local ret = orig(self, t, dt, time_left)
        local loaded = self:get_ammo_remaining_in_clip() - before
        if info and loaded > 0 then
            local taken = Ammo.ConsumeLooseKey(info.key, loaded)
            if taken < loaded then self:set_ammo_remaining_in_clip(before + taken) end
            Ammo.SyncTotal(self)
            Ammo.MarkPanelDirty()
        end
        return ret
    end
end

-- The pickup multipliers of the game (skills, crew ability, ammo type).
local function pickup_multipliers(base)
    local ok, low, high = pcall(function()
        local data = base._ammo_data
        local function from_upgrades()
            local pm = managers.player
            local value = pm:upgrade_value("player", "pick_up_ammo_multiplier", 1)
            value = value + pm:upgrade_value("player", "pick_up_ammo_multiplier_2", 1) - 1
            value = value + pm:crew_ability_upgrade_value("crew_scavenge", 0)
            return value
        end
        local low = data and data.ammo_pickup_min_mul or from_upgrades()
        local high = data and data.ammo_pickup_max_mul or from_upgrades()
        return low, high
    end)
    if ok and type(low) == "number" and type(high) == "number" then return low, high end
    return 1, 1
end

-- The game's pickup for an ammunition base the mod does not manage (the
-- underbarrel launcher of a gun).
local function vanilla_add(ammo_base, ratio, override)
    if ammo_base:get_ammo_max() == ammo_base:get_ammo_total() then return false, 0 end
    local amount, picked_up = override, true
    if not amount then
        local pickup = ammo_base._ammo_pickup or { 0, 0 }
        local low, high = pickup_multipliers(ammo_base)
        local rng = pickup[1] * low + (pickup[2] * high - pickup[1] * low) * math.random()
        picked_up = rng > 0
        amount = math.max(0, math.floor(rng + 0.5))
    end
    amount = math.floor(amount * (ratio or 1))
    local total = math.min(ammo_base:get_ammo_max(), math.max(0, ammo_base:get_ammo_total() + amount))
    ammo_base:set_ammo_total(total)
    return picked_up, amount
end

-- What is left over of a pickup that gave less than one round. A grenade
-- launcher gets a fraction of a round from a box; the fractions add up, so
-- enough boxes give a whole grenade.
Ammo.pickup_carry = Ammo.pickup_carry or {}

-- Picking up ammunition: the rounds become loose ammunition in the inventory.
local function make_add_ammo_hook(orig)
    return function(self, ratio, add_amount_override)
        if Ammo.SkipWeapon(self) then
            return orig(self, ratio, add_amount_override)
        end

        local info = Ammo.Identify(self)
        if not info then return orig(self, ratio, add_amount_override) end

        Ammo.SyncTotal(self)

        local picked_up, amount = false, 0
        local room = math.max(0, self:get_ammo_max() - self:get_ammo_total())

        if room > 0 then
            if add_amount_override then
                -- A pickup of a known size (an arrow, a bolt).
                amount = math.floor(add_amount_override * (ratio or 1))
                picked_up = true
            else
                local pickup = self._ammo_pickup
                if pickup then
                    local low, high = pickup_multipliers(self)
                    local rng = pickup[1] * low + (pickup[2] * high - pickup[1] * low) * math.random()
                    -- Like the game: the box is taken even when it rolled less
                    -- than one round; the fraction is kept for the next box.
                    picked_up = rng > 0
                    local exact = math.max(0, rng) * (ratio or 1) + (Ammo.pickup_carry[info.key] or 0)
                    amount = math.floor(exact)
                    Ammo.pickup_carry[info.key] = exact - amount
                end
            end

            amount = math.max(0, math.min(amount, room))

            if amount > 0 and not Ammo.AddLooseKey(info.key, amount, info) then
                -- No room in the inventory: the box stays where it is.
                Ammo.SyncTotal(self)
                return false, 0
            end
        end

        pcall(function()
            if not self.get_all_override_weapon_gadgets then return end
            for _, gadget in ipairs(self:get_all_override_weapon_gadgets()) do
                if gadget and gadget.ammo_base then
                    local p, a = vanilla_add(gadget:ammo_base(), ratio, add_amount_override)
                    picked_up = p or picked_up
                    amount = amount + a
                end
            end
        end)

        Ammo.SyncTotal(self)
        Ammo.MarkPanelDirty()

        return picked_up, amount
    end
end

-- An ammo bag: its rounds fill the magazines at once, the rest stays loose.
local function make_bag_hook(orig)
    return function(self, available, special)
        if not Ammo.settings.unblock_bag or Ammo.SkipWeapon(self) then
            return orig(self, available, special)
        end

        Ammo.SyncTotal(self)

        -- A weapon with magazines: the bag restocks the magazines (their own
        -- bullets, then new full ones). The game's part only for a gadget
        -- (an underbarrel launcher), with what the bag has left.
        if not Ammo.IsLooseFed(self) and Ammo.Identify(self) then
            local used = Ammo.BagRestock(self, available) or 0
            local rest = math.max(0, (tonumber(available) or 0) - used)
            local gadget = 0
            if rest > 0 then
                -- The main ammunition counts as full for the game.
                local total = self:get_ammo_total()
                self:set_ammo_total(self:get_ammo_max())
                local ok, r = pcall(orig, self, rest, special)
                if ok and type(r) == "number" then gadget = r end
                self:set_ammo_total(total)
            end
            Ammo.SyncTotal(self)
            Ammo.MarkPanelDirty()
            Ammo.RefreshHud()
            return used + gadget
        end

        local before = self:get_ammo_total()
        local ret = orig(self, available, special)
        local added = self:get_ammo_total() - before

        if added > 0 and Ammo.IsLooseFed(self) then
            -- No magazines: the bag's rounds become loose rounds.
            Ammo.AddLoose(self, added)
            Ammo.SyncTotal(self)
            Ammo.MarkPanelDirty()
            Ammo.RefreshHud()
        elseif added > 0 then
            local loose = Ammo.LooseOf(self)
            -- The rounds of the bag fill the magazines first. What does not fit
            -- stays as loose ammunition.
            local left = Ammo.FillMagazines(self, loose + added, added)
            Ammo.SetLoose(self, left)
            Ammo.SyncTotal(self)
            Ammo.MarkPanelDirty()
            Ammo.RefreshHud()
        end

        return ret
    end
end

local function make_need_ammo_hook(orig)
    return function(self)
        if orig(self) then return true end

        if Ammo.settings.unblock_bag then
            local player = Ammo.PlayerUnit()
            if player and player:inventory() == self and Ammo.MagazinesNeedFill(player) then
                return true
            end
            -- A bag restocks magazines: it is wanted while one is not full or
            -- one more fits.
            local selections = player and player:inventory() == self and self:available_selections()
            for _, sel in pairs(selections or {}) do
                local wep = sel.unit and sel.unit:base()
                if wep and not Ammo.SkipWeapon(wep) and Ammo.BagWanted(wep) then return true end
            end
        end

        return false
    end
end

-- Does any weapon of the player have room for loose rounds?
function Ammo.MagazinesNeedFill(player)
    local inventory = player and player:inventory()
    local selections = inventory and inventory:available_selections()
    if not selections then return false end

    for _, sel in pairs(selections) do
        local wep = sel.unit and sel.unit:base()
        if wep and not Ammo.SkipWeapon(wep) then
            local info = Ammo.Identify(wep)
            if info and not info.loose_fed then
                for _, entry in ipairs(Ammo.Magazines(info.key)) do
                    if Ammo.FillBullet(info, entry) then return true end
                end
            end
        end
    end

    return false
end

------------------------------------------------------------ the reload key

local function reload_held(state)
    local controller = state and state._controller
    if not controller or not controller.get_input_bool then return false end
    if controller.get_any_input and not controller:get_any_input() then return false end
    return controller:get_input_bool("reload") and true or false
end

local function tap_hold_time()
    local nqr = rawget(_G, "NQR")
    local retention = nqr and nqr.settings and nqr.settings.nqr_retention_time
    if type(retention) == "number" and retention > 0 then return retention end
    return Ammo.settings.hold_time or 0.2
end

local function holster_start(state, t, reason)
    if holster == reason then return true end
    if holster then return false end
    if state:_changing_weapon() then return false end

    local pl = Ammo.PlayerUnit()
    local inv = pl and pl:inventory()
    if not inv or not inv.equipped_selection then return false end

    holster = reason
    state:_start_action_unequip_weapon(t, { selection_wanted = inv:equipped_selection() })
    return true
end

local function holster_release(reason)
    if holster == reason then holster = nil end
end

local function holstered(state, t)
    local expire = state._unequip_weapon_expire_t
    return holster ~= nil and expire ~= nil and t >= expire
end

local function log_hold(state, text)
    if state._issr_hold_logged then return end
    state._issr_hold_logged = true
    log(text)
end

local function make_reload_hook(orig)
    return function(self, t, input)
        if not Ammo.settings.enabled then
            self._issr_hold_t = nil
            holster_release("refill")
            if Ammo.IsPanelVisible and Ammo.IsPanelVisible() then Ammo.SetPanel(false) end
            return orig(self, t, input)
        end

        local held = reload_held(self)
        local wep = Ammo.EquippedBase()
        local applicable = wep and not Ammo.SkipWeapon(wep)

        if held and applicable then
            if not self._issr_hold_t then
                self._issr_hold_t = t + tap_hold_time()
            end

            if t >= self._issr_hold_t then
                self._issr_held_long = true

                Ammo.SetPanel(true)

                local reloading = self._state_data and self._state_data.reload_expire_t
                local loose = Ammo.LooseOf(wep)

                if not reloading and loose > 0 and Ammo.NeedsFill(wep) then
                    if holster_start(self, t, "refill") then
                        if holstered(self, t) then
                            Ammo.StartJob(wep)
                        end
                    else
                        log_hold(self, "refill blocked, weapon busy (holster " .. tostring(holster) .. ")")
                    end
                else
                    holster_release("refill")
                    if loose > 0 and not reloading then
                        log_hold(self, "loose rounds cannot go anywhere right now")
                    end
                end
            end

            return false
        end

        holster_release("refill")

        local tap = self._issr_hold_t ~= nil and not self._issr_held_long

        self._issr_hold_t = nil
        self._issr_held_long = nil
        self._issr_hold_logged = nil

        if Ammo.IsPanelVisible and Ammo.IsPanelVisible() and not Ammo.settings.overlay_always then
            Ammo.SetPanel(false)
        end

        if tap then
            if applicable and Ammo.TryFastReload(self, t, wep, orig) then return true end
            return orig(self, t, { btn_reload_press = true })
        end

        return orig(self, t, input)
    end
end

-- More taps of R during a reload that has just started: the reload starts
-- again, faster, and ends that many times sooner than the first one would
-- have (counted from the first tap). Every tap must come within DOUBLE_TAP
-- seconds of the one before.
--   one gun:  2 taps  FAST_RELOAD faster, the old magazine is dropped
--   akimbo:   2 taps  AKIMBO_ONE faster, only one magazine is changed
--             3 taps  AKIMBO_DUMP faster, both old magazines are dropped
function Ammo.TryFastReload(state, t, wep, check_reload)
    local data = state._state_data
    local expire = data and data.reload_expire_t
    if not expire or not wep or Ammo.IsLooseFed(wep) then return false end
    local akimbo = Ammo.IsAkimbo(wep)
    local taps = wep._pdti_taps or 1
    if taps >= (akimbo and 3 or 2) then return false end
    local start = Ammo.track_wep == wep and Ammo.track_start or wep._pdti_reload_t
    local origin = wep._pdti_tap_origin or start
    local prev = wep._pdti_tap_t or start
    if not origin or not prev or t - prev > Ammo.DOUBLE_TAP then return false end
    if not Ammo.NextMagazine(wep) then return false end
    -- How long the first reload is without the mod's own factor.
    local base = wep._pdti_tap_base
    if not base then
        if not start then return false end
        base = (expire - start) * (wep._pdti_reload_factor or 1)
    end
    taps = taps + 1
    local speed = Ammo.FAST_RELOAD
    if akimbo then speed = taps == 2 and Ammo.AKIMBO_ONE or Ammo.AKIMBO_DUMP end
    local remaining = math.max(0.15, base / speed - math.max(0, t - origin))
    pcall(state._interupt_action_reload, state, t)
    -- The interrupt forgets the taps, so they are set after it.
    wep._pdti_taps = taps
    wep._pdti_tap_t = t
    wep._pdti_tap_origin = origin
    wep._pdti_tap_base = base
    wep._pdti_fast_mul = base / remaining
    if akimbo then
        wep._pdti_akimbo_mode = taps == 2 and "one" or "dump"
    else
        wep._pdti_dump = true
    end
    Ammo.track_start = nil
    Ammo.track_wep = nil
    local ok = pcall(check_reload, state, t, { btn_reload_press = true })
    if not ok or not (state._state_data and state._state_data.reload_expire_t) then
        clear_taps(wep)
        return false
    end
    if akimbo then
        log(string.format("R tapped %d times: akimbo %s reload (x%.2f)", taps, wep._pdti_akimbo_mode, wep._pdti_fast_mul))
    else
        log(string.format("R tapped twice: fast reload (x%.2f), the magazine is dropped", wep._pdti_fast_mul))
    end
    return true
end

-- The reload speed of the game, with the mod's factor: faster after a double
-- tap, slower when the old magazine has no free place.
local function make_reload_speed_hook(orig)
    return function(self, ...)
        local mul = orig(self, ...)
        if type(mul) ~= "number" or not Ammo.settings.enabled or Ammo.SkipWeapon(self) or Ammo.IsLooseFed(self) then
            return mul
        end
        local factor = 1
        if self._pdti_fast_mul then
            factor = self._pdti_fast_mul
        elseif Ammo.MustSwap(self) then
            factor = 1 / Ammo.SWAP_SLOWDOWN
        end
        self._pdti_reload_factor = factor
        local ok, now = pcall(function() return managers.player:player_timer():time() end)
        self._pdti_reload_t = ok and now or nil
        -- A bigger magazine takes longer to seat (kept out of the factor, so
        -- the tap timing stays right).
        return mul * factor * Ammo.SizeReloadFactor(self)
    end
end

local function make_interupt_hook(orig)
    return function(self, t, ...)
        local wep = Ammo.EquippedBase()
        local ret = orig(self, t, ...)
        if Ammo.settings.enabled and wep and not Ammo.SkipWeapon(wep) and not Ammo.IsLooseFed(wep) then
            reload_interrupted(wep)
            -- A fast reload that was interrupted is forgotten (TryFastReload
            -- sets its flags after interrupting the first reload).
            clear_taps(wep)
        end
        return ret
    end
end

local function make_holster_hook(orig)
    return function(self, t, input)
        if holster and self._unequip_weapon_expire_t then return end
        return orig(self, t, input)
    end
end

local function make_hud_hook(orig)
    return function(self, wtype, max_clip, current_clip, current_left, max, weapon_panel)
        orig(self, wtype, max_clip, current_clip, current_left, max, weapon_panel)

        pcall(function()
            if self._id ~= HUDManager.PLAYER_PANEL then return end

            local pl = Ammo.PlayerUnit()
            local inv = pl and pl:inventory()
            local unit = inv and inv:unit_by_selection(wtype == "primary" and 2 or 1)
            local base = alive(unit) and unit:base() or nil
            if not base then return end

            if Ammo.SkipWeapon(base) then return end
            local info = Ammo.Identify(base)
            -- A weapon loaded round by round shows its rounds, as in the game.
            if not info or info.loose_fed then return end

            local count = Ammo.MagCount(info.key)

            local panel = weapon_panel
            if not panel and self._player_panel then
                local weapons = self._player_panel:child("weapons_panel")
                panel = weapons and weapons:child(wtype .. "_weapon_panel")
            end

            local amt = panel and panel:child("ammo_total")
            if not amt then return end

            local zero = count < 10 and "00" or count < 100 and "0" or ""
            amt:set_text(zero .. tostring(count))
            amt:set_font_size(string.len(count) < 4 and 24 or 20)
            pcall(function()
                amt:set_range_color(0, string.len(zero), amt:color():with_alpha(0.5))
            end)
        end)
    end
end

------------------------------------------------------------ dropped mags

local PICKUP_RANGE = 250
local PICKUP_HOLD = 1
local AIM_RADIUS = 50
local mvec_from = Vector3()
local mvec_to = Vector3()
local mvec_dir = Vector3()
local mvec_v = Vector3()
local mvec_closest = Vector3()

local function can_pickup_dropped(tag)
    if not tag or not tag.queue_key then return false end
    local wep = Ammo.EquippedBase()
    local info = wep and Ammo.Identify(wep)
    local count = Ammo.MagCount(tag.queue_key)
    local cap = Ammo.MagAmountFor(tag.pid, tag.caliber, tag.name_id) * (tag.akimbo and 2 or 1) + Ammo.ExtraMags()
    if wep and wep._issr_mag_gone and info and info.key == tag.queue_key then
        cap = cap + 1
    end
    return count < cap
end

local function bar_stop(complete)
    holster_release("pickup")
end

local function clear_pickup()
    bar_stop(false)
    Ammo.pickup_tag = nil
    Ammo.pickup_t = nil
end

local function firearm_in_hand(state)
    local base = Ammo.EquippedBase()
    if not base or base.get_ammo_remaining_in_clip == nil or base._blueprint == nil then return false end
    if state._is_meleeing and state:_is_meleeing() then return false end
    local pl = Ammo.PlayerUnit()
    local inv = pl and pl:inventory()
    local sel = inv and inv.equipped_selection and inv:equipped_selection()
    return sel == nil or sel == 1 or sel == 2
end

local function find_aimed_tag(pos, rot)
    mvector3.set(mvec_from, pos)
    mvector3.set(mvec_to, rot:y())
    mvector3.multiply(mvec_to, PICKUP_RANGE)
    mvector3.add(mvec_to, mvec_from)

    local ray = World:raycast(mvec_from, mvec_to)
    local hit_dist = ray and mvector3.distance(mvec_from, ray.position) or PICKUP_RANGE
    local tag = ray and ray.unit and alive(ray.unit) and dropped[ray.unit:key()] or nil
    if tag then return tag end

    mvector3.set(mvec_dir, mvec_to)
    mvector3.subtract(mvec_dir, mvec_from)
    mvector3.normalize(mvec_dir)

    local best, best_along = nil, nil

    for _, cand in pairs(dropped) do
        if alive(cand.col) and can_pickup_dropped(cand) then
            mvector3.set(mvec_v, cand.col:position())
            mvector3.subtract(mvec_v, mvec_from)

            local along = mvector3.dot(mvec_v, mvec_dir)

            if along > 0 and along <= hit_dist then
                mvector3.set(mvec_closest, mvec_dir)
                mvector3.multiply(mvec_closest, along)
                mvector3.subtract(mvec_v, mvec_closest)

                local perp = mvector3.length(mvec_v)

                if perp <= AIM_RADIUS and (not best_along or along < best_along) then
                    best = cand
                    best_along = along
                end
            end
        end
    end

    return best
end

local function update_pickup(state, t)
    for k, tag in pairs(dropped) do
        if not alive(tag.col) then dropped[k] = nil end
    end

    if not Ammo.settings.enabled or next(dropped) == nil then
        clear_pickup()
        return
    end

    local pl = Ammo.PlayerUnit()
    local cam = pl and pl:camera()
    local pos = cam and cam:position()
    local rot = cam and cam:rotation()

    if not pos or not rot then
        clear_pickup()
        return
    end

    local tag = find_aimed_tag(pos, rot)

    if not tag or not can_pickup_dropped(tag) then
        clear_pickup()
        return
    end

    if Ammo.pickup_tag ~= tag then
        Ammo.pickup_tag = tag
        pcall(function()
            managers.hud:show_interact({
                text = managers.localization:btn_macro("interact", false) .. " " .. L("issr_pickup", "Pick up magazine")
            })
        end)
    end

    local ctrl = state._controller
    local held = ctrl and ctrl.get_input_bool and ctrl:get_input_bool("interact")

    if not held then
        if Ammo.pickup_t or holster == "pickup" then
            bar_stop(false)
            Ammo.pickup_t = nil
            Ammo.pickup_tag = nil
        end
        return
    end

    if not Ammo.pickup_t then
        local in_hand = firearm_in_hand(state) and state._unequip_weapon_expire_t == nil
        local need_holster = holster == "pickup" or in_hand

        if need_holster and (not holster_start(state, t, "pickup") or not holstered(state, t)) then return end

        Ammo.pickup_t = t
        managers.hud:show_interaction_bar(0, PICKUP_HOLD)
    end

    local progress = math.min(1, (t - Ammo.pickup_t) / PICKUP_HOLD)

    managers.hud:set_interaction_bar_width(progress * PICKUP_HOLD, PICKUP_HOLD)

    if progress < 1 then return end

    local ok = Ammo.PickupDropped(tag)

    bar_stop(ok)
    pcall(function() managers.hud:remove_interact() end)

    if ok then
        if alive(tag.col) then tag.col:set_slot(0) end
        if alive(tag.mag) then tag.mag:set_slot(0) end
        dropped[tag.key] = nil
        pcall(function() pl:sound():play("pickup_ammo") end)
    end

    Ammo.pickup_tag = nil
    Ammo.pickup_t = nil
end

-- Picks a magazine that lies on the floor up: it becomes an inventory item.
function Ammo.PickupDropped(tag)
    if not tag then return false end
    local info = {
        key = tag.queue_key, capacity = Ammo.MagCapacity(tag.pid, tag.caliber),
        caliber = tag.caliber, pid = tag.pid
    }
    local spec = nil
    if tag.typed then
        info.typed = true
        info.capacity = tag.base_capacity or info.capacity
        spec = { size = tag.size, bullet = tag.bullet, load = tag.load }
    end
    local ok = Ammo.AddMagazineKey(tag.queue_key, tag.rounds or 0, info, nil, spec)
    if ok then
        local wep = Ammo.EquippedBase()
        if wep then pcall(Ammo.SyncTotal, wep) end
        Ammo.MarkPanelDirty()
        Ammo.RefreshHud()
    end
    return ok
end

Ammo.Dropped = dropped

------------------------------------------------------------- the bullets

-- The weapon whose magazine counts: an akimbo second gun fires the main
-- weapon's bullets. Only the player's assault rifles and SMGs.
local function typed_base(base)
    if not base then return nil end
    local parent = base.parent_weapon
    if parent then
        local ok, pb = pcall(function() return parent:base() end)
        if ok and pb then base = pb end
    end
    if not Ammo.settings.enabled or not Ammo.IsOurs(base) or not Ammo.Typed(base) then return nil end
    return base
end
Ammo.TypedBase = typed_base

-- The damage of a shot: the bullet's multiplier. The game reads the
-- shoot-through flags right after this, so they follow the bullet here.
local function make_damage_hook(orig)
    return function(self, ...)
        local damage = orig(self, ...)
        local base = typed_base(self)
        if not base or type(damage) ~= "number" then return damage end
        local bullet = Ammo.ShotBullet(base)
        Ammo.ApplyBullet(self, bullet)
        return damage * (Ammo.BULLETS[Ammo.BulletId(bullet)].damage or 1)
    end
end

-- Armour plates: hollow points never pierce them, armour piercing always.
local function make_pierce_hook(orig)
    return function(self, ...)
        local chance = orig(self, ...)
        local base = typed_base(self)
        if not base then return chance end
        local def = Ammo.BULLETS[Ammo.BulletId(Ammo.FiredBullet(base))]
        if def.pierce ~= nil then return def.pierce end
        return chance
    end
end

-- The recoil of a shot (called by the game once per shot, after it fired).
-- Shots count as one burst when the next comes within one and a half times
-- the gun's fire interval (plus a little slack); a pause starts over.
Ammo.BURST_SLACK = 0.05

local function now_time()
    local ok, t = pcall(function() return Application:time() end)
    if ok and type(t) == "number" then return t end
    return os.clock()
end

local function fire_interval(base)
    local ok, value = pcall(function()
        local rate = base:weapon_tweak_data().fire_mode_data.fire_rate
        local mul = base.fire_rate_multiplier and base:fire_rate_multiplier() or 1
        return rate / (mul or 1)
    end)
    if ok and type(value) == "number" and value > 0 then return value end
    return 0.1
end

-- The bullet's recoil factor for this shot, and the shots in a row so far.
function Ammo.BulletRecoil(base)
    local def = Ammo.BULLETS[Ammo.BulletId(Ammo.FiredBullet(base))]
    local t = now_time()
    local last = base._pdti_recoil_t
    local streak = 0
    if last and t - last <= fire_interval(base) * 1.5 + Ammo.BURST_SLACK then
        streak = (base._pdti_recoil_streak or 0) + 1
    end
    base._pdti_recoil_t = t
    base._pdti_recoil_streak = streak
    if not def.recoil then return 1, streak end
    local build = math.min(streak, def.recoil_build_max or 0) * (def.recoil_build or 0)
    return def.recoil * (1 + build), streak
end

local function make_recoil_hook(orig)
    return function(self, ...)
        local value = orig(self, ...)
        local base = typed_base(self)
        if not base or type(value) ~= "number" then return value end
        local ok, mul = pcall(Ammo.BulletRecoil, base)
        if ok and type(mul) == "number" then return value * mul end
        return value
    end
end

-- The bodies of the arms and the legs.
Ammo.LIMB_BODIES = {
    "rag_LeftArm", "rag_RightArm", "rag_LeftForeArm", "rag_RightForeArm",
    "rag_LeftUpLeg", "rag_RightUpLeg", "rag_LeftLeg", "rag_RightLeg"
}
local limb_ids = nil

function Ammo.IsLimbBody(name)
    if name == nil then return false end
    if not limb_ids then
        limb_ids = {}
        for _, body in ipairs(Ammo.LIMB_BODIES) do
            local ok, id = pcall(Idstring, body)
            if ok then limb_ids[#limb_ids + 1] = id end
        end
    end
    for _, id in ipairs(limb_ids) do
        if name == id then return true end
    end
    return false
end

-- Hollow points: every hit on an arm or a leg is a critical hit (when the
-- enemy can take critical hits at all).
local function make_crit_hook(orig)
    return function(self, attack_data, ...)
        local ok, crit, damage = pcall(function()
            if type(attack_data) ~= "table" or not attack_data.col_ray then return nil end
            if attack_data.attacker_unit ~= Ammo.PlayerUnit() then return nil end
            local weapon = attack_data.weapon_unit
            if not alive(weapon) then return nil end
            local base = typed_base(weapon:base())
            if not base then return nil end
            local def = Ammo.BULLETS[Ammo.BulletId(Ammo.FiredBullet(base))]
            if not def.limb_crit then return nil end
            local body = attack_data.col_ray.body
            if not body or not Ammo.IsLimbBody(body:name()) then return nil end
            if not self:can_be_critical(attack_data) then return nil end
            local tweak = self._char_tweak or {}
            local critical_hits = tweak.critical_hits or {}
            local mul = critical_hits.damage_mul or tweak.headshot_dmg_mul
            local dmg = attack_data.damage
            return true, mul and dmg * mul or (self._health or dmg) * 10
        end)
        if ok and crit then return true, damage end
        return orig(self, attack_data, ...)
    end
end

------------------------------------------------- akimbo: a button per gun

-- The akimbo weapon of the player whose guns follow the mouse buttons.
local function akimbo_buttons(wep)
    return wep ~= nil and Ammo.settings.enabled and Ammo.settings.akimbo_buttons ~= false
        and Ammo.IsAkimbo(wep) and Ammo.IsOurs(wep) and not Ammo.SkipWeapon(wep)
end
Ammo.AkimboButtons = akimbo_buttons

-- The left mouse button (fire) fires the left gun, the right one (aim) the
-- right gun. The game sees one fire button, pressed while either is; aiming
-- is off with these guns. wep._pdti_want says which guns fire this frame.
local function make_input_hook(orig)
    return function(self, t, dt, paused, ...)
        local input = orig(self, t, dt, paused, ...)
        if type(input) ~= "table" then return input end
        local wep = Ammo.EquippedBase()
        if not akimbo_buttons(wep) then
            if wep then wep._pdti_want = nil end
            return input
        end
        local ls, rs = input.btn_primary_attack_state, input.btn_steelsight_state
        local lp, rp = input.btn_primary_attack_press, input.btn_steelsight_press
        local lr, rr = input.btn_primary_attack_release, input.btn_steelsight_release
        local ok, mode = pcall(wep.fire_mode, wep)
        local auto = ok and mode == "auto"
        wep._pdti_want = {
            left = (lp or (auto and ls)) and true or false,
            right = (rp or (auto and rs)) and true or false
        }
        -- One trigger at a time for the game: a new press while the other
        -- button is held starts a new shot.
        if not auto and self._shooting and ((lp and rs and not rp) or (rp and ls and not lp)) then
            if self._check_stop_shooting then pcall(self._check_stop_shooting, self) end
        end
        input.btn_primary_attack_press = (lp or rp) and true or nil
        input.btn_primary_attack_state = (ls or rs) and true or false
        input.btn_primary_attack_release = ((lr or rr) and not (ls or rs)) and true or nil
        input.btn_steelsight_press = nil
        input.btn_steelsight_release = nil
        input.btn_steelsight_state = false
        if self._state_data and self._state_data.in_steelsight and self._end_action_steelsight then
            pcall(self._end_action_steelsight, self, t)
        end
        return input
    end
end

-- Fires the guns whose buttons are down, each from its own magazine.
-- Body health: a black arm cannot fire the akimbo gun in its hand
-- (1 = the left gun and arm, 2 = the right).
function Ammo.ArmBlocked(g)
    local body = PDTI.Body
    if not body or not body.ArmBlocked then return false end
    local ok, value = pcall(body.ArmBlocked, g == 1 and "arm_l" or "arm_r")
    return ok and value == true
end

Ammo.ARM_HINT_INTERVAL = 2
local function arm_hint(g)
    local t = now_time()
    if Ammo.arm_hint_t and t - Ammo.arm_hint_t < Ammo.ARM_HINT_INTERVAL then return end
    Ammo.arm_hint_t = t
    local side = g == 1 and "left" or "right"
    pcall(function()
        managers.hud:show_hint({ text = "Your " .. side .. " arm is black: the " .. side .. " gun cannot fire" })
    end)
end

local function make_akimbo_fire_hook(orig)
    return function(self, ...)
        local want = self._pdti_want
        local blocked = { false, false }
        local ours = Ammo.settings.enabled and Ammo.IsAkimbo(self) and Ammo.IsOurs(self) and not Ammo.SkipWeapon(self)
        if ours then blocked = { Ammo.ArmBlocked(1), Ammo.ArmBlocked(2) } end
        if type(want) ~= "table" or not akimbo_buttons(self) then
            -- The game fires both guns; with a black arm only the other one.
            if not (blocked[1] or blocked[2]) then return orig(self, ...) end
            want = { left = true, right = true }
        end
        local cls = rawget(_G, "AkimboWeaponBase")
        local super = cls and cls.super
        if not super or not super.fire then return orig(self, ...) end
        local result, empty = nil, false

        local function fire_gun(g, fn, base, ...)
            self._pdti_fire_gun = g
            local done, r = pcall(fn, base, ...)
            -- The round leaves this gun's magazine, not the fuller one.
            if done then pcall(Ammo.AkimboPair, self) end
            self._pdti_fire_gun = nil
            if not done then error(r, 0) end
            return r
        end

        local pair = Ammo.AkimboPair(self) or { 0, 0 }
        if want.right and blocked[2] then
            arm_hint(2)
        elseif want.right then
            if pair[2] > 0 then
                result = fire_gun(2, super.fire, self, ...)
            else
                empty = true
            end
        end
        if want.left and blocked[1] then
            arm_hint(1)
        elseif want.left then
            pair = Ammo.AkimboPair(self) or { 0, 0 }
            local second = self._second_gun
            if pair[1] > 0 and alive(second) then
                local sb = second:base()
                local fn = sb.super and sb.super.fire or super.fire
                local r = fire_gun(1, fn, sb, ...)
                if r then
                    if not want.right then pcall(sb._fire_sound, sb) end
                    pcall(function() managers.hud:set_ammo_amount(self:selection_index(), self:ammo_info()) end)
                    pcall(sb.tweak_data_anim_play, sb, "fire")
                end
                result = result or r
            else
                empty = true
            end
        end
        -- The gun of the pressed button is empty: a click.
        if not result and empty and self.dryfire then pcall(self.dryfire, self) end
        Ammo.MarkPanelDirty()
        return result
    end
end

-------------------------------------------------------------- the install

-- Every hook has to be in place before the first reload. The weapon classes
-- do not exist yet when the mod loads, so the installation is repeated until
-- every required hook is in.
local REQUIRED_HOOKS = {
    { "NewRaycastWeaponBase", "can_reload", make_can_reload_hook },
    { "NewRaycastWeaponBase", "on_reload", make_on_reload_hook },
    { "NewRaycastWeaponBase", "update_reloading", make_update_reloading_hook },
    { "RaycastWeaponBase", "add_ammo", make_add_ammo_hook },
    { "RaycastWeaponBase", "add_ammo_from_bag", make_bag_hook },
    { "PlayerInventory", "need_ammo", make_need_ammo_hook },
    { "PlayerStandard", "_update_equip_weapon_timers", make_holster_hook },
    { "PlayerStandard", "_check_action_reload", make_reload_hook },
    { "PlayerStandard", "_interupt_action_reload", make_interupt_hook },
    { "HUDTeammate", "set_ammo_amount_by_type", make_hud_hook }
}

-- These functions only exist with the NQR mod (its reload stages and its
-- dropped magazines). Without NQR the mod derives the stages from the reload
-- timer, so they are not needed.
local OPTIONAL_HOOKS = {
    -- The reload speed (double tap, no free place). Without it reloads keep
    -- the game's speed.
    { "NewRaycastWeaponBase", "reload_speed_multiplier", make_reload_speed_hook },
    { "NewRaycastWeaponBase", "update_r_stage", make_stage_hook },
    { "NewRaycastWeaponBase", "drop_magazine_object", make_drop_hook },
    -- The bullets of assault rifles and SMGs.
    { "NewRaycastWeaponBase", "_get_current_damage", make_damage_hook },
    { "NewRaycastWeaponBase", "armor_piercing_chance", make_pierce_hook },
    { "NewRaycastWeaponBase", "recoil_multiplier", make_recoil_hook },
    { "CopDamage", "roll_critical_hit", make_crit_hook },
    -- Akimbo: a mouse button per gun.
    { "PlayerStandard", "_get_input", make_input_hook },
    { "AkimboWeaponBase", "fire", make_akimbo_fire_hook }
}

local reported_missing = nil

-- The hooks are installed as soon as the classes exist. This is called every
-- frame until then, so the order in which the game loads its classes does not
-- matter.
function Ammo.InstallHooks()
    if hooks_installed then
        -- NQR can load after this mod: its functions are wrapped when they appear.
        for _, entry in ipairs(OPTIONAL_HOOKS) do wrap(entry[1], entry[2], entry[3]) end
        return true
    end

    local missing = {}
    for _, entry in ipairs(REQUIRED_HOOKS) do
        if not wrap(entry[1], entry[2], entry[3]) then
            missing[#missing + 1] = entry[1] .. "." .. entry[2]
        end
    end
    for _, entry in ipairs(OPTIONAL_HOOKS) do wrap(entry[1], entry[2], entry[3]) end

    if #missing == 0 then
        hooks_installed = true
        log("the ammunition hooks are in place")
        return true
    end

    -- Reported once per set of missing functions, so the log shows what the
    -- mod is still waiting for.
    local text = table.concat(missing, ", ")
    if text ~= reported_missing and rawget(_G, "PlayerStandard") and rawget(_G, "NewRaycastWeaponBase") then
        reported_missing = text
        log("waiting for: " .. text)
    end
    return false
end

-- Follows the reload timer. Marks the reload as started and, without NQR
-- (which has its own reload stages), creates the magazine stages.
local function track_reload(state, t, base, applicable)
    local data = state._state_data
    local expire = data and data.reload_expire_t

    if not (expire and applicable and base) then
        Ammo.track_wep = nil
        Ammo.track_start = nil
        Ammo.track_stage = nil
        return
    end

    if Ammo.track_wep ~= base or not Ammo.track_start then
        Ammo.track_wep = base
        Ammo.track_start = t
        Ammo.track_stage = 0
        reload_started(base)
    end

    if rawget(_G, "NQR") ~= nil then return end

    local total = expire - Ammo.track_start
    local frac = total > 0 and (t - Ammo.track_start) / total or 1

    if Ammo.track_stage < 1 and frac >= stage_out() then
        Ammo.track_stage = 1
        mag_left(base, base._issr_reload_dropped)
        mag_out_drop(base)
    end

    if Ammo.track_stage < 2 and frac >= stage_in() then
        Ammo.track_stage = 2
        mag_entered(base)
    end
end

-- Makes sure the weapon has its starting magazines and the right ammunition
-- maximum.
local function prepare_weapon(base)
    Ammo.EnsureSupply(base)

    -- A weapon loaded round by round keeps the game's ammunition maximum.
    if base.set_ammo_max and not Ammo.IsLooseFed(base) then
        local want = Ammo.MaxTotal(base)
        if want and base:get_ammo_max() ~= want then
            base:set_ammo_max(want)
        end
    end
end

-- Runs fn for every weapon of the player the mod manages.
function Ammo.ForEachWeapon(fn)
    local pl = Ammo.PlayerUnit()
    if not pl then return end
    local ok, selections = pcall(function() return pl:inventory():available_selections() end)
    if not ok or type(selections) ~= "table" then return end
    -- The primary first: its magazines get the first places in the rig.
    local order = {}
    for index, sel in pairs(selections) do order[#order + 1] = { index = index, sel = sel } end
    table.sort(order, function(a, b)
        local ia, ib = tonumber(a.index) or 0, tonumber(b.index) or 0
        return ia > ib
    end)
    for _, entry in ipairs(order) do
        local sel = entry.sel
        local wep = sel.unit and sel.unit:base()
        if wep and not Ammo.SkipWeapon(wep) then
            local done, err = pcall(fn, wep)
            if not done then log("weapon update failed: " .. tostring(err)) end
        end
    end
end

local ensured = setmetatable({}, { __mode = "k" })

function Ammo.EnsureAllSupplies()
    Ammo.ForEachWeapon(function(wep)
        if ensured[wep] then return end
        ensured[wep] = true
        prepare_weapon(wep)
    end)
end

-- Called every frame from the mod's game hook.
function Ammo.GameTick(state, t, dt, paused)
    -- The weapon classes appear later than the mod, so this is repeated until
    -- every hook is in place.
    Ammo.InstallHooks()

    if paused then return end

    local base = Ammo.EquippedBase()
    local applicable = base ~= nil and not Ammo.SkipWeapon(base)

    if base and applicable then
        prepare_weapon(base)
    end

    -- Every weapon gets its supply as soon as it exists, so the reserve the
    -- game gave a weapon that is loaded round by round is not lost.
    pcall(Ammo.EnsureAllSupplies)

    -- The weapon's slot shows the magazine in the gun.
    Ammo.ForEachWeapon(Ammo.SyncGunSlot)

    -- The inventory changed (a magazine was moved or thrown away, rounds were
    -- used): the totals, the counter and the panel follow at once.
    local revision = PDTI.inventory_revision or 0
    if revision ~= Ammo.last_revision then
        Ammo.last_revision = revision
        Ammo.ForEachWeapon(function(wep) Ammo.SyncTotal(wep) end)
        Ammo.MarkPanelDirty()
        Ammo.RefreshHud()
    end

    -- An arrow that was shot leaves the inventory.
    if applicable and Ammo.NoReload(base) and base:get_ammo_total() ~= base._pdti_synced then
        Ammo.SyncTotal(base)
        Ammo.MarkPanelDirty()
    end

    -- The panel follows the gun: a new gun or a changed clip makes it dirty,
    -- so the magazine row is up to date at once.
    if applicable then
        local clip = base:get_ammo_remaining_in_clip()
        local unit = Ammo.EquippedUnit()
        local ok, wep_key = pcall(function() return unit and unit:key() or nil end)
        if not ok then wep_key = nil end

        if clip ~= Ammo.last_clip or wep_key ~= Ammo.last_wep then
            Ammo.last_clip = clip
            Ammo.last_wep = wep_key
            Ammo.MarkPanelDirty()
        end
    end

    if state then
        track_reload(state, t, base, applicable and not Ammo.IsLooseFed(base))
    end

    if Ammo.settings.overlay_always and Ammo.settings.enabled then
        local want = applicable
        if want ~= (Ammo.IsPanelVisible and Ammo.IsPanelVisible()) then
            Ammo.SetPanel(want)
        end
    end

    if holster == "refill" and not reload_held(state) then
        holster_release("refill")
    end

    if state then update_pickup(state, t) end

    if holster == "refill" and holstered(state, t) then
        Ammo.Tick(dt)
    end

    if Ammo.IsPanelVisible and Ammo.IsPanelVisible() then
        if Ammo.TakePanelDirty() then Ammo.RefreshPanel() end
    end
end

Ammo.InstallHooks()
