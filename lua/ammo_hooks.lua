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

local log = PDTI.Logger("PDTI AMMO")

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
    wep._pdti_unload = nil
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
    -- A gun without a magazine has none to take out or drop.
    wep._pdti_started_empty = Ammo.GunWithoutMagazine(wep) or nil
end

-- The old magazine leaves the gun. Without NQR the mod decides whether it
-- really hits the floor: with a magazine-drop mod (drop_magazine_object) its
-- drop is used, otherwise the mod's own (Ammo.OwnDrop).
local function mag_out_drop(wep)
    if rawget(_G, "NQR") ~= nil or wep._issr_reload_dropped or wep._pdti_started_empty then return end
    if wep.drop_magazine_object then
        pcall(wep.drop_magazine_object, wep)
    elseif Ammo.OwnDrop then
        local ok, err = pcall(Ammo.OwnDrop, wep)
        if not ok then log("the magazine could not be dropped: " .. tostring(err)) end
    end
end

-------------------------------------------------------------- the reload

-- Forgets the taps of a reload (it ended or was interrupted).
local clear_taps

local show_hint = PDTI.Hint

-- The player timer's time (it stops while paused), or nil.
local function player_time()
    local ok, now = pcall(function() return managers.player:player_timer():time() end)
    return ok and now or nil
end

local function current_state()
    local ok, state = pcall(function() return managers.player:player_unit():movement():current_state() end)
    return ok and state or nil
end

-- "gun" was chosen with the wheel and R pressed: the reload animation runs
-- until the magazine leaves the gun, then it stops. The magazine goes into
-- the inventory and the gun has none.
local function finish_unload(state, wep, t)
    wep._pdti_unload = nil
    wep._issr_mag_left_rounds = nil
    wep._issr_drop_count = 0
    local ok = Ammo.Unload(wep)
    if not ok then show_hint("No room for the magazine: it stays in the gun") end
    state = state or current_state()
    if state and state._interupt_action_reload then
        pcall(state._interupt_action_reload, state, t)
        pcall(function() state._ext_camera:play_redirect(state:get_animation("idle")) end)
    end
    if clear_taps then clear_taps(wep) end
    Ammo.MarkPanelDirty()
    return ok
end
Ammo.FinishUnload = finish_unload

-- How long the panel stays up after the wheel turned.
Ammo.CHOICE_SHOW = 2

-- Which way the wheel turned this frame: 1 down (the next magazine), -1 up,
-- nil when it did not turn. The wheel is read from the mouse itself (as BLT
-- reads its keybinds): the game does not always pass it on as a key.
local function wheel_dir()
    local function pressed(name)
        local ok, v = pcall(function() return Input:mouse():pressed(Idstring(name)) end)
        return ok and v and true or false
    end
    if pressed("mouse wheel up") then return -1 end
    if pressed("mouse wheel down") then return 1 end
    return nil
end
Ammo.WheelDir = wheel_dir

-- Keys that do something other than move: they stop loading a magazine.
-- Moving, jumping, crouching, sprinting and the stats screen do not.
Ammo.ACTION_KEYS = {
    "btn_primary_attack_press", "btn_steelsight_press", "btn_reload_press", "btn_melee_press",
    "btn_throw_grenade_press", "btn_projectile_press", "btn_interact_press", "btn_interact_secondary_press",
    "btn_use_item_press", "btn_switch_weapon_press", "btn_primary_choice", "btn_weapon_gadget_press",
    "btn_weapon_firemode_press", "btn_cash_inspect_press"
}

function Ammo.ActionPressed(input)
    if type(input) ~= "table" then return false end
    for _, key in ipairs(Ammo.ACTION_KEYS) do
        if input[key] then return true end
    end
    -- The mouse wheel chooses magazines: an action too.
    local ok, dir = pcall(wheel_dir)
    return ok and dir ~= nil
end

-- Typing in the chat or using a menu: the wheel is not ours.
local function wheel_free()
    if PDTI.IsUIOpen and PDTI.IsUIOpen() then return false end
    local ok, chat = pcall(function() return managers.hud:chat_focus() end)
    if ok and chat then return false end
    return true
end

local function busy(state)
    local function call(name)
        local fn = state[name]
        if type(fn) ~= "function" then return false end
        local ok, v = pcall(fn, state)
        return ok and v and true or false
    end
    return call("_is_reloading") or call("_changing_weapon") or call("_is_meleeing") or call("_interacting")
        or call("_is_throwing_projectile") or call("is_shooting_count") or state._use_item_expire_t ~= nil
end

-- The wheel (the game's "switch weapon") chooses the next magazine of a
-- weapon fed from magazines. The keys 1 and 2 still change the weapon.
-- During a reload the wheel does nothing.
function Ammo.HandleWheel(state, input, t)
    if not input then return false end
    if not Ammo.On() or Ammo.settings.wheel_choose == false then return false end
    local dir = wheel_dir()
    if not dir or not wheel_free() then return false end
    local wep = Ammo.EquippedBase()
    if not wep or Ammo.SkipWeapon(wep) or Ammo.NoReload(wep) then return false end
    if Ammo.IsLooseFed(wep) then
        -- A shotgun tube: the wheel chooses the next kind of shell.
        local info = Ammo.Identify(wep)
        if not info or info.family ~= "shell" then return false end
        input.btn_switch_weapon_press = nil
        local id = Ammo.CycleShell(wep, dir)
        if id then
            show_hint("Next shell: " .. Ammo.BulletName(id, "shell"))
            Ammo.panel_until = (tonumber(t) or 0) + Ammo.CHOICE_SHOW
            pcall(Ammo.SetPanel, true)
        end
        return true
    end
    -- The wheel turned: it does not switch the weapon (a key bound to
    -- "switch weapon" still does, since the wheel did not turn then).
    input.btn_switch_weapon_press = nil
    local reloading = wep._issr_in_reload or (state._state_data and (state._state_data.reload_expire_t
        or state._state_data.reload_enter_expire_t))
    if reloading then return true end
    if Ammo.CycleChoice(wep, dir) then
        Ammo.panel_until = (tonumber(t) or 0) + Ammo.CHOICE_SHOW
        pcall(Ammo.SetPanel, true)
    end
    return true
end

-- A tap of R that does what the wheel chose: take the magazine out of the
-- gun, or load a chosen magazine even into a full gun. Returns true when it
-- handled the tap.
function Ammo.ChosenReload(state, t, wep)
    local info = Ammo.Identify(wep)
    if not info or info.loose_fed or Ammo.NoReload(wep) then return false end
    local choice = Ammo.CurrentChoice(wep)
    if choice == "gun" then
        if busy(state) then return true end
        local places, why = Ammo.UnloadPlaces(wep)
        if not places and why == "none" then
            -- The slot may not show the gun's magazine yet (a weapon just
            -- put into your hands): once more after a sync.
            pcall(Ammo.SyncGunSlot, wep)
            places, why = Ammo.UnloadPlaces(wep)
        end
        if not places then
            -- "none": the gun has a magazine but its slot holds something
            -- else (another weapon's magazine put there).
            show_hint(why == "none" and "The weapon's magazine slot holds another magazine: move it out first"
                or "No room for the magazine in the rig, pockets or backpack")
            return true
        end
        wep._pdti_unload = true
        pcall(state._start_action_reload_enter, state, t)
        local data = state._state_data or {}
        if not (data.reload_expire_t or data.reload_enter_expire_t) then wep._pdti_unload = nil end
        return true
    end
    -- A magazine chosen on purpose goes in even when the gun is full (the
    -- game would not reload a full gun).
    if choice and Ammo.selection[info.key] == choice and not busy(state) then
        local ok, full = pcall(function()
            if wep.clip_full then return wep:clip_full() end
            return wep:get_ammo_remaining_in_clip() >= wep:get_ammo_max_per_clip()
        end)
        if ok and full then
            pcall(state._start_action_reload_enter, state, t)
            return true
        end
    end
    return false
end

function clear_taps(wep)
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
            -- Old magazines are listed only when none fell to the floor (no
            -- "Drop My Mag"): even a fast reload keeps them then.
            if mode == "dump" then
                log(string.format("akimbo fast reload: no magazine could be dropped, %d round(s) kept", mag.rounds))
            end
            Ammo.ReturnMagazine(self, Ammo.EjectRounds(self, mag.rounds), mag.spec)
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
        if self._pdti_unload then
            finish_unload(nil, self, nil)
            return
        end

        local info = Ammo.Identify(self)
        if not info then return orig(self, ...) end

        Ammo.EnsureSupply(self)

        -- Loaded round by round: the rounds come out of the loose ammunition.
        if info.loose_fed then
            Ammo.SyncTotal(self)
            local before = self:get_ammo_remaining_in_clip()
            local ret = orig(self, ...)
            local loaded = self:get_ammo_remaining_in_clip() - before
            if loaded > 0 and info.family == "shell" then
                -- Shells of the chosen kind go in on top (the last one in is
                -- fired first).
                local wanted = Ammo.selection[info.key]
                local _, used = Ammo.LoadShells(self, before, loaded)
                if wanted and used[1] and used[1][1] ~= wanted then
                    show_hint(string.format("No %s left: loading %s", Ammo.BulletName(wanted, "shell"),
                        Ammo.BulletName(used[1][1], "shell")))
                    Ammo.selection[info.key] = nil
                end
                Ammo.ApplyLoaded(self)
            elseif loaded > 0 then
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
                -- R tapped twice, but no magazine fell (the game drops
                -- magazines as objects only with a mod such as "Drop My
                -- Mag"): there is nothing to pick up, so it is kept.
                log(string.format("fast reload: no magazine could be dropped, %d round(s) kept", actual))
            end
            -- A skill can fill the old magazine (Bulletstorm ace): the next one
            -- is taken out first, so the reload does not load it again.
            local refilled = Ammo.EjectRounds(self, actual)
            if Ammo.MustSwap(self) then
                -- No free place: the old magazine goes where the new one was.
                next_mag = Ammo.SwapMagazine(self, refilled)
            elseif refilled ~= actual then
                next_mag = Ammo.TakeMagazine(self)
                Ammo.ReturnMagazine(self, refilled)
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

        -- The magazine taken out goes into the inventory, not on the floor.
        if self._pdti_unload then return end

        -- Without NQR this mod decides whether a magazine is dropped: only
        -- during a reload, at most once per reload, and only as far as the
        -- drop mode allows.
        if rawget(_G, "NQR") == nil then
            if not self._issr_in_reload then return orig(self, ...) end
            if self._issr_reload_dropped then return end

            local mode = math.max(0, math.min(2, math.floor((Ammo.settings.drop_mode or 1) + 0.5)))
            local rounds = math.max(self:get_ammo_remaining_in_clip() - Ammo.ChamberOf(self), 0)

            -- A fast reload throws the magazine away whatever the drop mode.
            if not self._pdti_dump and (mode == 0 or (mode == 1 and rounds > 0)) then return end

            self._issr_reload_dropped = true
        end

        -- What falls is caught where the game registers it (add_magazine),
        -- not by the length of its list: at the game's limit of magazines on
        -- the floor the oldest are removed and the list is replaced.
        local em = managers.enemy
        local added = {}
        local own_add = em and rawget(em, "add_magazine")
        local real_add = em and em.add_magazine
        if real_add then
            em.add_magazine = function(m, mag, col, ...)
                added[#added + 1] = { mag, col }
                return real_add(m, mag, col, ...)
            end
        end
        local function restore()
            if real_add then em.add_magazine = own_add end
        end

        local ok, ret = pcall(orig, self, ...)
        if not ok then log("dropping the magazine failed: " .. tostring(ret)); ret = nil end

        -- The game's own drop_magazine_object (or another mod's) may drop
        -- nothing for the player's gun: the mod drops it itself then.
        if #added == 0 and orig ~= Ammo.FallbackDrop and Ammo.FallbackDrop then
            local ok2, err = pcall(Ammo.FallbackDrop, self)
            if not ok2 then log("the magazine could not be dropped: " .. tostring(err)) end
        end
        restore()

        if #added > 0 then
            local rounds = math.max(self:get_ammo_remaining_in_clip() - Ammo.ChamberOf(self), 0)
            local info = Ammo.Identify(self)
            local loaded = info and info.typed and Ammo.LoadedSpec(self)

            if info then
                for _, entry in ipairs(added) do
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
                            sized = info.sized,
                            family = info.family,
                            factory_id = info.factory_id,
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

        if not Ammo.On() or Ammo.SkipWeapon(self) then return ret end

        local cycle = self.r_cycle
        local stage = self.r_stage
        local name = cycle and stage and cycle[stage] or nil

        if name ~= self._issr_stage then
            self._issr_stage = name

            if name == "r_mag_out" and self._pdti_unload then
                finish_unload(nil, self, player_time())
            elseif name == "r_mag_out" then
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
        -- Taking the magazine out needs no magazine to load.
        if self._pdti_unload then return true end
        if Ammo.On() and not Ammo.SkipWeapon(self) then
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
        if not Ammo.On() or Ammo.SkipWeapon(self) or not Ammo.IsLooseFed(self) then
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

-- Ammo boxes give loose rounds up to two full stacks per weapon (all its
-- bullets counted). With both guns there the boxes stay on the floor.
Ammo.BOX_STACKS = 2
function Ammo.BoxLimit()
    local def = PDTI.items and PDTI.items[Ammo.LOOSE_ITEM or "loose_ammo"]
    return Ammo.BOX_STACKS * (tonumber(def and def.max_stack) or 100)
end

function Ammo.BoxRoom(wep)
    local info = Ammo.Identify(wep)
    if not info then return math.huge end
    return math.max(0, Ammo.BoxLimit() - Ammo.LooseOfKey(info.key))
end

-- Does no gun of the player take rounds from a box any more?
function Ammo.BoxesFull(unit)
    local ok, full = pcall(function()
        local inventory = unit and unit:inventory()
        if not inventory then return false end
        local any = false
        for _, sel in pairs(inventory:available_selections() or {}) do
            local wep = sel.unit and sel.unit:base()
            if wep and not Ammo.SkipWeapon(wep) and Ammo.Identify(wep) then
                any = true
                if Ammo.BoxRoom(wep) > 0 then return false end
            end
        end
        return any
    end)
    return ok and full == true
end

-- A plain ammo box (not a throwable, not one weapon's arrows) is left on
-- the floor when both guns are at the limit. (restoration-mod would take it
-- anyway when your grenades are not full.)
local function make_box_pickup_hook(orig)
    return function(self, unit, ...)
        if Ammo.On() and not self._projectile_id and not self._weapon_category
            and unit ~= nil and unit == Ammo.PlayerUnit() and Ammo.BoxesFull(unit) then
            return false
        end
        return orig(self, unit, ...)
    end
end

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
        -- The inventory decides how much you can carry (AddLooseKey below).
        -- A weapon loaded round by round (a launcher, a bow) keeps the game's
        -- maximum.
        local room = math.huge
        if info.loose_fed or Ammo.NoReload(self) then
            room = math.max(0, self:get_ammo_max() - self:get_ammo_total())
        end
        -- Boxes fill the loose rounds of a weapon up to two stacks (0.21.3).
        if not add_amount_override then room = math.min(room, Ammo.BoxRoom(self)) end

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
        -- restoration-mod: a weapon's _ammo_ratio scales what a share of the
        -- bag is worth (the game divides by it and returns the share times it).
        local ratio = tonumber(self._ammo_ratio) or 1
        if ratio <= 0 then ratio = 1 end
        if not Ammo.IsLooseFed(self) and Ammo.Identify(self) then
            local used = (Ammo.BagRestock(self, (tonumber(available) or 0) / ratio) or 0) * ratio
            used = math.max(0, math.min(tonumber(available) or 0, used))
            local rest = math.max(0, (tonumber(available) or 0) - used)
            local gadget = 0
            if rest > 0 then
                -- The main ammunition counts as full for the game.
                local total = self:get_ammo_total()
                self:set_ammo_total(self:get_ammo_max())
                local ok, r = pcall(orig, self, rest, special)
                if ok and type(r) == "number" then gadget = math.max(0, r) end
                self:set_ammo_total(total)
            end
            Ammo.SyncTotal(self)
            Ammo.MarkPanelDirty()
            Ammo.RefreshHud()
            return used + gadget
        end

        -- The inventory can hold more rounds than the game's maximum. The game
        -- works out what it takes as "1 - total / max": above the maximum that
        -- is less than nothing, and the bag got MORE uses from it (0.21.3).
        -- The game sees at most its maximum, and never takes less than nothing.
        local before = self:get_ammo_total()
        local max = tonumber(self:get_ammo_max()) or before
        local seen = math.min(before, max)
        if seen ~= before then self:set_ammo_total(seen) end
        local ok, ret = pcall(orig, self, available, special)
        local added = math.max(0, self:get_ammo_total() - seen)
        if seen ~= before or not ok then self:set_ammo_total(before + (ok and added or 0)) end
        if not ok then error(ret, 0) end
        if type(ret) == "number" and ret < 0 then ret = 0 end

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
        if not Ammo.On() then
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
                    -- Fully Loaded ace: from the pouch the gun stays in hand.
                    if holster ~= "refill" and Ammo.PouchPackAllowed and Ammo.PouchPackAllowed(self, wep) then
                        Ammo.StartJob(wep)
                        Ammo.pouch_packing = true
                    elseif holster_start(self, t, "refill") then
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

        if Ammo.IsPanelVisible and Ammo.IsPanelVisible() and not Ammo.settings.overlay_always
            and not (Ammo.panel_until and t < Ammo.panel_until) then
            Ammo.SetPanel(false)
        end

        if tap then
            if applicable and not wep._pdti_unload and Ammo.TryFastReload(self, t, wep, orig) then return true end
            local reloading = self._state_data and (self._state_data.reload_expire_t or self._state_data.reload_enter_expire_t)
            if applicable and not reloading and Ammo.ChosenReload(self, t, wep) then return true end
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
        if type(mul) ~= "number" or not Ammo.On() or Ammo.SkipWeapon(self) or Ammo.IsLooseFed(self) then
            return mul
        end
        local factor = 1
        if Ammo.GunWithoutMagazine(self) then
            -- Nothing to take out: the reload skips that part.
            factor = Ammo.EMPTY_GUN_SPEED
        elseif self._pdti_fast_mul then
            factor = self._pdti_fast_mul
        elseif Ammo.MustSwap(self) then
            factor = 1 / Ammo.SWAP_SLOWDOWN
        end
        self._pdti_reload_factor = factor
        self._pdti_reload_t = player_time()
        -- A bigger magazine takes longer to seat (kept out of the factor, so
        -- the tap timing stays right).
        return mul * factor * Ammo.SizeReloadFactor(self)
    end
end

-- The mod's own magazine drop, for when no magazine-drop mod is installed: a
-- copy of the gun's magazine part falls in a collision box, as the game does
-- for other players' magazines (HuskPlayerMovement), and goes into the enemy
-- manager's list, where the drop hook finds it and pickup works as usual.
-- Units are spawned only when they are loaded (an unloaded unit would crash
-- the game).
local IDS_UNIT = nil
local function unit_loaded(ids)
    local ok, has = pcall(function()
        IDS_UNIT = IDS_UNIT or Idstring("unit")
        return PackageManager:has(IDS_UNIT, ids)
    end)
    return ok and has and true or false
end

Ammo.MAG_COLLISIONS = {
    pistol = { "units/payday2/weapons/box_collision/box_collision_small_pistol", "rp_box_collision_small" },
    smg = { "units/payday2/weapons/box_collision/box_collision_small_smg", "rp_box_collision_small" },
    rifle = { "units/payday2/weapons/box_collision/box_collision_medium_ar", "rp_box_collision_medium" },
    large_plastic = { "units/payday2/weapons/box_collision/box_collision_large_plastic", "rp_box_collision_large" },
    large_metal = { "units/payday2/weapons/box_collision/box_collision_large_metal", "rp_box_collision_large" }
}
Ammo.MAG_COLLISIONS.small = Ammo.MAG_COLLISIONS.pistol
Ammo.MAG_COLLISIONS.medium = Ammo.MAG_COLLISIONS.rifle
Ammo.MAG_COLLISIONS.large = Ammo.MAG_COLLISIONS.large_metal

-- Which collision box the weapon's magazine falls in: the crew weapon's
-- (what other players' copies use), otherwise by the weapon's category.
function Ammo.MagazineCollision(wep)
    local wtd = tweak_data and tweak_data.weapon
    local crew = wtd and wep._name_id and wtd[wep._name_id .. "_crew"]
    local kind = crew and crew.pull_magazine_during_reload
    if type(kind) == "string" and Ammo.MAG_COLLISIONS[kind] then return kind end
    local own = wtd and wep._name_id and wtd[wep._name_id]
    local cats = own and own.categories or {}
    for _, c in ipairs(cats) do
        if c == "pistol" then return "pistol" end
        if c == "smg" then return "smg" end
        if c == "lmg" or c == "minigun" then return "large_metal" end
    end
    return "rifle"
end

-- The magazine part of the gun (its unit and its unit name).
function Ammo.MagazinePart(wep)
    local parts_td = tweak_data and tweak_data.weapon and tweak_data.weapon.factory
        and tweak_data.weapon.factory.parts
    if not parts_td or type(wep._parts) ~= "table" then return nil end
    for part_id, part in pairs(wep._parts) do
        local td = parts_td[part_id]
        if td and td.type == "magazine" and part.name and part.unit and alive(part.unit) then
            return part, part_id, td
        end
    end
    return nil
end

function Ammo.SpawnMagazineUnit(wep)
    local part, _, td = Ammo.MagazinePart(wep)
    if not part then return false, "the weapon has no magazine part" end
    local col = Ammo.MAG_COLLISIONS[Ammo.MagazineCollision(wep)] or Ammo.MAG_COLLISIONS.rifle
    local col_ids = Idstring(col[1])
    if not unit_loaded(part.name) then return false, "the magazine unit is not loaded" end
    if not unit_loaded(col_ids) then return false, "the collision box is not loaded" end

    local pos, rot = part.unit:position(), part.unit:rotation()
    local center = pos
    pcall(function() center = part.unit:oobb():center() end)
    local mag = World:spawn_unit(part.name, pos, rot)
    if not mag then return false, "the magazine unit could not be spawned" end
    local box = World:spawn_unit(col_ids, center, rot)
    if not box then
        pcall(function() mag:set_slot(0) end)
        return false, "the collision box could not be spawned"
    end
    box:link(Idstring(col[2]), mag)

    -- An empty magazine shows no rounds.
    local bullets = td and td.bullet_objects
    if bullets and Ammo.EmptyOnDrop(wep) then
        pcall(function()
            local offset = bullets.offset or 0
            for i = 1 + offset, bullets.amount + offset do
                local object = mag:get_object(Idstring(bullets.prefix .. i))
                if object then object:set_visibility(false) end
            end
        end)
    end

    -- It falls out of the gun, downwards and a little away.
    pcall(function()
        local dir = wep._unit:rotation():z() * -math.random(65, 80)
        box:push(10, dir)
    end)

    managers.enemy:add_magazine(mag, box)
    return true
end

-- Rounds left in the magazine that is dropped (the chambered one stays).
function Ammo.EmptyOnDrop(wep)
    local ok, rounds = pcall(function() return wep:get_ammo_remaining_in_clip() - Ammo.ChamberOf(wep) end)
    return ok and rounds <= 0
end

local own_drop_failed = {}
local function own_drop_orig(self)
    local ok, why = Ammo.SpawnMagazineUnit(self)
    if not ok and why and not own_drop_failed[why] then
        own_drop_failed[why] = true
        log("the magazine is not dropped (kept in the inventory): " .. tostring(why))
    end
end

-- The mod's own drop goes through the same rules (drop mode, once per reload,
-- the record for pickup) as a magazine-drop mod's.
Ammo.FallbackDrop = own_drop_orig
Ammo.OwnDrop = make_drop_hook(own_drop_orig)

local function make_interupt_hook(orig)
    return function(self, t, ...)
        local wep = Ammo.EquippedBase()
        local ret = orig(self, t, ...)
        if Ammo.On() and wep and not Ammo.SkipWeapon(wep) and not Ammo.IsLooseFed(wep) then
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

local PICKUP_HOLD = 1
local AIM_RADIUS = 50
local mvec_from = Vector3()
local mvec_to = Vector3()
local mvec_dir = Vector3()
local mvec_v = Vector3()
local mvec_closest = Vector3()

-- A magazine on the floor can be picked up when it fits in the inventory.
local function can_pickup_dropped(tag)
    return Ammo.DroppedFits(tag)
end

local function bar_stop(complete)
    holster_release("pickup")
end

-- The "pick up" hint is the game's interaction text: it stays until it is
-- removed, so it is removed whenever no magazine is aimed at.
local function hide_pickup_hint()
    if not Ammo.pickup_hint then return end
    Ammo.pickup_hint = nil
    pcall(function() managers.hud:remove_interact() end)
    pcall(function() managers.hud:hide_interaction_bar(false) end)
end

local function clear_pickup()
    bar_stop(false)
    hide_pickup_hint()
    Ammo.pickup_tag = nil
    Ammo.pickup_t = nil
end

local pickup_failed = {}
local function pickup_problem(reason)
    if pickup_failed[reason] then return end
    pickup_failed[reason] = true
    log("a dropped magazine could not be picked up: " .. reason)
end

-- The game is interacting with something else (or could: an object is
-- highlighted): that comes first.
local function game_interaction(state)
    local ok, busy = pcall(function()
        if state._interacting and state:_interacting() then return true end
        local inter = state._interaction or (managers and managers.interaction)
        return inter and inter.active_unit and inter:active_unit() ~= nil
    end)
    return ok and busy and true or false
end
Ammo.GameInteraction = game_interaction

local function find_aimed_tag(pos, rot)
    mvector3.set(mvec_from, pos)
    mvector3.set(mvec_to, rot:y())
    local range = Ammo.PickupRange()
    mvector3.multiply(mvec_to, range)
    mvector3.add(mvec_to, mvec_from)

    local ray = World:raycast(mvec_from, mvec_to)
    local hit_dist = ray and mvector3.distance(mvec_from, ray.position) or range
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

    if not Ammo.On() or next(dropped) == nil then
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

    if not tag or not can_pickup_dropped(tag) or game_interaction(state) then
        clear_pickup()
        return
    end

    if Ammo.pickup_tag ~= tag or not Ammo.pickup_hint then
        Ammo.pickup_tag = tag
        Ammo.pickup_t = nil
        Ammo.pickup_hint = true
        pcall(function()
            managers.hud:show_interact({
                text = managers.localization:btn_macro("interact", false) .. " " .. L("issr_pickup", "Pick up magazine")
            })
        end)
    end

    -- Held: what the game read this frame (Ammo.interact_held, from the input
    -- hook), or the controller itself.
    local ctrl = state._controller
    local held = Ammo.interact_held
    if not held and ctrl and ctrl.get_input_bool then
        local ok, v = pcall(ctrl.get_input_bool, ctrl, "interact")
        held = ok and v
    end

    if not held then
        if Ammo.pickup_t then
            Ammo.pickup_t = nil
            pcall(function() managers.hud:hide_interaction_bar(false) end)
        end
        return
    end

    -- A plain hold, like the game's own pickups (no holstering: the weapon
    -- switch is changed by other mods and could keep it from finishing).
    if not Ammo.pickup_t then
        Ammo.pickup_t = t
        pcall(function() managers.hud:show_interaction_bar(0, PICKUP_HOLD) end)
    end

    local progress = math.min(1, (t - Ammo.pickup_t) / PICKUP_HOLD)
    pcall(function() managers.hud:set_interaction_bar_width(progress * PICKUP_HOLD, PICKUP_HOLD) end)

    if progress < 1 then return end

    local ok, picked = pcall(Ammo.PickupDropped, tag)
    if not ok then
        pickup_problem(tostring(picked))
        picked = false
    elseif not picked then
        pickup_problem("it did not fit in the inventory")
    end

    if picked then
        if alive(tag.col) then tag.col:set_slot(0) end
        if alive(tag.mag) then tag.mag:set_slot(0) end
        dropped[tag.key] = nil
        pcall(function() pl:sound():play("pickup_ammo") end)
    end

    clear_pickup()
end
Ammo.UpdatePickup = update_pickup

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
        -- Tags from before 0.20.0 have no family: a size means a rifle.
        info.family = tag.family or "rifle"
        info.sized = tag.sized or (tag.family == nil and tag.size ~= nil) or nil
        info.factory_id = tag.factory_id
        info.capacity = tag.base_capacity or info.capacity
        spec = { size = tag.size, bullet = tag.bullet, load = tag.load }
    end
    local ok = Ammo.AddMagazineKey(tag.queue_key, tag.rounds or 0, info, nil, spec)
    if not ok then ok = Ammo.AddMagazineKey(tag.queue_key, tag.rounds or 0, info, { "backpack" }, spec) end
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

-- An akimbo second gun counts as its parent weapon.
local function parent_base(base)
    local parent = base.parent_weapon
    if parent then
        local ok, pb = pcall(function() return parent:base() end)
        if ok and pb then return pb end
    end
    return base
end

-- The weapon whose magazine counts: an akimbo second gun fires the main
-- weapon's bullets. Only the player's assault rifles and SMGs.
local function typed_base(base)
    if not base then return nil end
    base = parent_base(base)
    if not Ammo.On() or not Ammo.IsOurs(base) then return nil end
    if Ammo.Typed(base) then return base end
    -- LMGs: their rounds work like rifle bullets.
    local info = Ammo.Identify(base)
    if not info or info.family ~= "lmg" or Ammo.SkipWeapon(base) then return nil end
    return base
end
Ammo.TypedBase = typed_base

-- The weapon whose shells count, for a shotgun (an akimbo second gun fires
-- the main weapon's shells).
local function shell_base(base)
    if not base then return nil end
    base = parent_base(base)
    if not Ammo.On() or not Ammo.IsOurs(base) then return nil end
    local info = Ammo.Identify(base)
    if not info or info.family ~= "shell" or Ammo.SkipWeapon(base) then return nil end
    return base
end
Ammo.ShellBase = shell_base

-- The damage of a shot: the bullet's multiplier. The game reads the
-- shoot-through flags right after this, so they follow the bullet here.
-- A shotgun: the shell being fired leaves the top of the load and the gun
-- takes that shell's profile (the game's own values for that ammunition
-- type) before the game works out the damage and the pellets.
local function make_damage_hook(orig)
    return function(self, ...)
        local shells = PDTI.Shells
        local sbase = shells and shell_base(self)
        if sbase then
            local shell = Ammo.ShotBullet(sbase)
            shells.Apply(self, shell)
            return orig(self, ...)
        end
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

local now_time = PDTI.AppTime

local function fire_interval(base)
    local ok, value = pcall(function()
        local rate = base:weapon_tweak_data().fire_mode_data.fire_rate
        local mul = base.fire_rate_multiplier and base:fire_rate_multiplier() or 1
        return rate / (mul or 1)
    end)
    if ok and type(value) == "number" and value > 0 then return value end
    return 0.1
end

-- Is the player's weapon resting on its bipod?
function Ammo.OnBipod()
    local ok, state = pcall(function() return managers.player:current_state() end)
    return ok and state == "bipod"
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
    if def.bipod_recoil and Ammo.OnBipod() then return def.bipod_recoil, streak end
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
        -- An HE blast whose critical hit this mod already decided: the game
        -- does not roll a second time (vanilla rolls in damage_explosion).
        if type(attack_data) == "table" and attack_data._pdti_crit_decided then
            local damage, clamp = ...
            damage = tonumber(damage) or attack_data.damage
            if tonumber(clamp) and tonumber(damage) then damage = math.min(damage, clamp) end
            return false, damage
        end
        -- The game passes the damage (and a cap) itself since 2026.
        local passed, clamp = ...
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
            local limb = body and Ammo.IsLimbBody(body:name())
            -- A skill can make every hit on some enemies a crit (cloakers).
            if not limb and not (Ammo.hp_crit_any and Ammo.hp_crit_any(self)) then return nil end
            if not self:can_be_critical(attack_data) then return nil end
            local tweak = self._char_tweak or {}
            local critical_hits = tweak.critical_hits or {}
            local mul = critical_hits.damage_mul or tweak.headshot_dmg_mul
            local dmg = tonumber(passed) or tonumber(attack_data.damage)
            if not dmg then return nil end
            local out = mul and dmg * mul or (self._health or dmg) * 10
            if tonumber(clamp) then out = math.min(out, clamp) end
            return true, out
        end)
        if ok and crit then
            Ammo.SureCrit(self, attack_data, "hp")
            return true, damage
        end
        return orig(self, attack_data, ...)
    end
end

-- A sure crit (HP on a limb, HE on a bulldozer or a turret): the skills hear
-- of it through Ammo.on_sure_crit(dmg_ext, attack_data, kind, turret).
function Ammo.SureCrit(dmg_ext, attack_data, kind, turret)
    local f = Ammo.on_sure_crit
    if type(f) ~= "function" then return end
    local ok, err = pcall(f, dmg_ext, attack_data, kind, turret)
    if not ok then log("a sure crit hook failed: " .. tostring(err)) end
end

-- HE rounds (LMG): the blast is a critical hit by the player's crit chance,
-- like a bullet, and always on a bulldozer or a turret. (Restoration's
-- explosions never roll one; the game's own roll is skipped for these, so
-- vanilla does not roll twice.)
function Ammo.IsDozer(dmg_ext)
    local ok, dozer = pcall(function()
        local base = dmg_ext._unit and dmg_ext._unit:base()
        local name = base and base._tweak_table
        if type(name) == "string" and name:find("^tank") then return true end
        local tags = dmg_ext._char_tweak and dmg_ext._char_tweak.tags
        if type(tags) == "table" then
            for _, tag in pairs(tags) do if tag == "tank" then return true end end
        end
        return false
    end)
    return ok and dozer == true
end

-- What a critical hit multiplies by on this enemy (or turret).
Ammo.HE_CRIT_MUL = 2
local function crit_mul(dmg_ext)
    local tweak = type(dmg_ext._char_tweak) == "table" and dmg_ext._char_tweak or {}
    local hits = type(tweak.critical_hits) == "table" and tweak.critical_hits or {}
    return tonumber(hits.damage_mul) or tonumber(tweak.headshot_dmg_mul) or Ammo.HE_CRIT_MUL
end

-- The HE blast this attack is part of, or nil.
local function he_blast(attack_data)
    local blast = Ammo.he_blast
    if not blast or type(attack_data) ~= "table" or attack_data.variant == "stun" then return nil end
    if not tonumber(attack_data.damage) then return nil end
    if attack_data.attacker_unit ~= Ammo.PlayerUnit() then return nil end
    if blast.weapon ~= nil and attack_data.weapon_unit ~= blast.weapon then return nil end
    local def = Ammo.BULLETS.explosive
    if not (def and def.blast_crit) then return nil end
    return blast
end

-- The crit roll of the game, done here: the game's own roll_critical_hit
-- differs between versions (the one in the game since 2026 needs the damage
-- as its second argument and failed on nil, which crashed the game, 0.21.4),
-- so it is not called. The same sums: the enemy's base chance plus the
-- player's crit chance times the enemy's multiplier, if this weapon can crit
-- with explosions at all.
Ammo.crit_roll = function() return math.random() end
function Ammo.RollCrit(dmg_ext, attack_data)
    local ok, crit = pcall(function()
        if type(dmg_ext.can_be_critical) == "function" and not dmg_ext:can_be_critical(attack_data) then
            return false
        end
        local tweak = type(dmg_ext._char_tweak) == "table" and dmg_ext._char_tweak or {}
        local hits = type(tweak.critical_hits) == "table" and tweak.critical_hits or {}
        local chance = (tonumber(hits.base_chance) or 0)
        local player = 0
        pcall(function() player = tonumber(managers.player:critical_hit_chance()) or 0 end)
        chance = chance + player * (tonumber(hits.player_chance_multiplier) or 1)
        return chance > 0 and Ammo.crit_roll() < chance
    end)
    return ok and crit == true
end

function Ammo.HeCrit(dmg_ext, attack_data, turret)
    if not he_blast(attack_data) then return false end
    local def = Ammo.BULLETS.explosive
    local crit, damage = false, attack_data.damage
    if def.sure_crit and (turret or Ammo.IsDozer(dmg_ext)) then
        -- An anti-armour round: heavy_mul times the damage, then the crit.
        crit, damage = true, attack_data.damage * (tonumber(def.heavy_mul) or 1) * crit_mul(dmg_ext)
        attack_data._pdti_sure_crit = true
    else
        crit = Ammo.RollCrit(dmg_ext, attack_data)
        if crit then damage = attack_data.damage * crit_mul(dmg_ext) end
    end
    attack_data._pdti_crit_decided = true
    if crit then
        attack_data.damage = damage
        attack_data.critical_hit = true
        pcall(function() managers.hud:on_crit_confirmed() end)
        if attack_data._pdti_sure_crit then Ammo.SureCrit(dmg_ext, attack_data, "he", turret) end
    end
    return crit
end

-- HE rounds stun: a hit enemy who lives through the blast may be dazed (the
-- concussion grenade's stun, the game's own stun_hit). Bulldozers have their
-- own chance (none by default: they take sure critical hits instead).
Ammo.stun_roll = function() return math.random() end
function Ammo.HeStun(dmg_ext, attack_data)
    local def = Ammo.BULLETS.explosive
    local chance = tonumber(def.stun_chance) or 0
    if Ammo.IsDozer(dmg_ext) then chance = tonumber(def.dozer_stun_chance) or 0 end
    if chance <= 0 or dmg_ext._dead or type(dmg_ext.stun_hit) ~= "function" then return false end
    local col_ray = attack_data.col_ray
    if type(col_ray) ~= "table" or not col_ray.position then return false end
    local civilian = false
    pcall(function() civilian = CopDamage.is_civilian(dmg_ext._unit:base()._tweak_table) end)
    if civilian then return false end
    if Ammo.stun_roll() >= chance then return false end
    local ok, err = pcall(dmg_ext.stun_hit, dmg_ext, { variant = "explosion", damage = 0,
        attacker_unit = attack_data.attacker_unit, weapon_unit = attack_data.weapon_unit, col_ray = col_ray })
    if not ok then log("HE stun failed: " .. tostring(err)) end
    if ok and type(Ammo.on_he_stun) == "function" then pcall(Ammo.on_he_stun, dmg_ext) end
    return ok
end

local function make_he_crit_hook(turret)
    return function(orig)
        return function(self, attack_data, ...)
            local is_he = he_blast(attack_data) ~= nil
            local ok, err = pcall(Ammo.HeCrit, self, attack_data, turret)
            if not ok then log("HE critical hit failed: " .. tostring(err)) end
            local result = { orig(self, attack_data, ...) }
            if is_he and not turret then
                local ok2, err2 = pcall(Ammo.HeStun, self, attack_data)
                if not ok2 then log("HE stun failed: " .. tostring(err2)) end
            end
            return unpack(result, 1, table.maxn(result))
        end
    end
end

------------------------------------------------- akimbo: a button per gun

-- The akimbo weapon of the player whose guns follow the mouse buttons.
local function akimbo_buttons(wep)
    return wep ~= nil and Ammo.On() and Ammo.settings.akimbo_buttons ~= false
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
        if Ammo.LoadActive and Ammo.LoadActive() and Ammo.ActionPressed(input) then
            Ammo.StopLoad("stopped")
        end
        pcall(Ammo.HandleWheel, self, input, t)
        -- The interact key while a dropped magazine is aimed at picks it up:
        -- the game does not also shout at nobody.
        Ammo.interact_held = input.btn_interact_state and true or false
        if Ammo.pickup_tag and Ammo.pickup_hint then
            input.btn_interact_press = nil
            input.btn_interact_release = nil
            input.btn_interact_state = false
        end
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
    PDTI.Hint("Your " .. side .. " arm is black: the " .. side .. " gun cannot fire")
end

local function make_akimbo_fire_hook(orig)
    return function(self, ...)
        local want = self._pdti_want
        local blocked = { false, false }
        local ours = Ammo.On() and Ammo.IsAkimbo(self) and Ammo.IsOurs(self) and not Ammo.SkipWeapon(self)
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
-- Not needed for the hooks above to be in place (loaded with the pickups).
local LATE_HOOKS = {
    { "AmmoClip", "_pickup", make_box_pickup_hook }
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
    -- HE rounds: critical hits, sure ones on bulldozers and turrets.
    { "CopDamage", "damage_explosion", make_he_crit_hook(false) },
    { "SentryGunDamage", "damage_explosion", make_he_crit_hook(true) },
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
        for _, entry in ipairs(LATE_HOOKS) do wrap(entry[1], entry[2], entry[3]) end
        return true
    end

    local missing = {}
    for _, entry in ipairs(REQUIRED_HOOKS) do
        if not wrap(entry[1], entry[2], entry[3]) then
            missing[#missing + 1] = entry[1] .. "." .. entry[2]
        end
    end
    for _, entry in ipairs(OPTIONAL_HOOKS) do wrap(entry[1], entry[2], entry[3]) end
    for _, entry in ipairs(LATE_HOOKS) do wrap(entry[1], entry[2], entry[3]) end

    if #missing == 0 then
        hooks_installed = true
        log("the ammunition hooks are in place")
        if NewRaycastWeaponBase.drop_magazine_object then
            log("drop_magazine_object exists (the game's or a mod's); if it drops nothing, this mod drops the magazine")
        else
            log("magazines are dropped by this mod (no magazine-drop mod installed)")
        end
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
        if base._pdti_unload then
            finish_unload(state, base, t)
            return
        end
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
-- Runs every frame: the scratch lists are reused (one pair per nesting depth,
-- fn may run it again); no closures.
local function selections_of(pl) return pl:inventory():available_selections() end
local scratch_index, scratch_sel, scratch_depth = {}, {}, 0
local function selection_number(index) return tonumber(index) or 0 end

-- Sorts the selections into the scratch lists and runs fn on each weapon.
-- An error here (a broken unit) still reaches the caller, but only after
-- ForEachWeapon has cleaned up.
local function visit_selections(fn, selections, indexes, sels)
    local n = 0
    for index, sel in pairs(selections) do
        -- insertion sort, highest selection number first
        local key = selection_number(index)
        local i = n
        while i > 0 and selection_number(indexes[i]) < key do
            indexes[i + 1], sels[i + 1] = indexes[i], sels[i]
            i = i - 1
        end
        indexes[i + 1], sels[i + 1] = index, sel
        n = n + 1
    end
    for i = 1, n do
        local sel = sels[i]
        local wep = sel.unit and sel.unit:base()
        if wep and not Ammo.SkipWeapon(wep) then
            local done, err = pcall(fn, wep)
            if not done then log("weapon update failed: " .. tostring(err)) end
        end
    end
end

function Ammo.ForEachWeapon(fn)
    local pl = Ammo.PlayerUnit()
    if not pl then return end
    local ok, selections = pcall(selections_of, pl)
    if not ok or type(selections) ~= "table" then return end
    -- The primary first: its magazines get the first places in the rig.
    scratch_depth = scratch_depth + 1
    local depth = scratch_depth
    local indexes, sels = scratch_index[depth], scratch_sel[depth]
    if not indexes then
        indexes, sels = {}, {}
        if depth <= 8 then scratch_index[depth], scratch_sel[depth] = indexes, sels end
    end
    local done, err = pcall(visit_selections, fn, selections, indexes, sels)
    -- Always cleared and unwound, also after an error: no stale units kept,
    -- the depth does not creep up.
    for i in pairs(indexes) do indexes[i] = nil end
    for i in pairs(sels) do sels[i] = nil end
    scratch_depth = depth - 1
    if not done then error(err, 0) end
end

local ensured = setmetatable({}, { __mode = "k" })

local function ensure_one(wep)
    if ensured[wep] then return end
    ensured[wep] = true
    prepare_weapon(wep)
end

function Ammo.EnsureAllSupplies()
    Ammo.ForEachWeapon(ensure_one)
end

-- Called every frame from the mod's game hook.
function Ammo.GameTick(state, t, dt, paused)
    -- The weapon classes appear later than the mod, so this is repeated until
    -- every hook is in place.
    Ammo.InstallHooks()

    -- In the safehouse the weapons are the game's own: nothing to follow.
    if paused or PDTI.InSafehouse() then return end

    -- Loose rounds dropped onto a magazine in the inventory screen.
    if Ammo.LoadTick then pcall(Ammo.LoadTick, dt) end

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

    if Ammo.settings.overlay_always and Ammo.On() then
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
    elseif Ammo.pouch_packing then
        if holster == nil and state and reload_held(state) and Ammo.PouchPackAllowed
            and Ammo.PouchPackAllowed(state, base) then
            Ammo.Tick(dt)
        else
            Ammo.pouch_packing = nil
        end
    end

    if Ammo.IsPanelVisible and Ammo.IsPanelVisible() then
        if Ammo.TakePanelDirty() then Ammo.RefreshPanel() end
    end
end

Ammo.InstallHooks()
