-- Shared offline test environment: mock json/log/SavePath and a fake BeardLib
-- MenuUI that REJECTS parameters not listed in the BeardLib docs, so typos in
-- the renderer are caught without launching the game.
local M = {}

function M.setup(root, tmp)
  os.execute("rm -rf " .. tmp .. " && mkdir -p " .. tmp)
  _G.SavePath = tmp
  M.logs = {}
  _G.log = function(m) M.logs[#M.logs + 1] = m end

  local function enc(v)
    local t = type(v)
    if t == "table" then
      if #v > 0 or next(v) == nil then
        local o = {} for _, x in ipairs(v) do o[#o + 1] = enc(x) end
        return "[" .. table.concat(o, ",") .. "]"
      end
      local o = {}
      for k, x in pairs(v) do o[#o + 1] = string.format("%q", tostring(k)) .. ":" .. enc(x) end
      return "{" .. table.concat(o, ",") .. "}"
    elseif t == "string" then return (string.format("%q", v):gsub("\\\n", "\\n"))
    else return tostring(v) end
  end
  local function dec(s)
    local i = 1
    local function ws() i = s:find("%S", i) or #s + 1 end
    local val
    local function str()
      local j, out = i + 1, {}
      while true do
        local c = s:sub(j, j)
        if c == "" then error("unterminated") end
        if c == '"' then break end
        if c == "\\" then j = j + 1; c = s:sub(j, j); c = ({ n = "\n", t = "\t" })[c] or c end
        out[#out + 1] = c; j = j + 1
      end
      i = j + 1; return table.concat(out)
    end
    function val()
      ws(); local c = s:sub(i, i)
      if c == "{" then
        i = i + 1; local r = {}; ws()
        if s:sub(i, i) == "}" then i = i + 1 return r end
        while true do
          ws(); local k = str(); ws(); assert(s:sub(i, i) == ":"); i = i + 1
          r[k] = val(); ws(); local d = s:sub(i, i); i = i + 1
          if d == "}" then return r elseif d ~= "," then error("bad obj") end
        end
      elseif c == "[" then
        i = i + 1; local r = {}; ws()
        if s:sub(i, i) == "]" then i = i + 1 return r end
        while true do
          r[#r + 1] = val(); ws(); local d = s:sub(i, i); i = i + 1
          if d == "]" then return r elseif d ~= "," then error("bad arr") end
        end
      elseif c == '"' then return str()
      elseif s:sub(i, i + 3) == "true" then i = i + 4 return true
      elseif s:sub(i, i + 4) == "false" then i = i + 5 return false
      elseif s:sub(i, i + 3) == "null" then i = i + 4 return nil
      else local n = s:match("^-?[%d%.eE+-]+", i); if not n then error("bad value") end i = i + #n return tonumber(n) end
    end
    local r = val(); ws(); if i <= #s then error("trailing") end return r
  end
  _G.json = { encode = enc, decode = dec }
  M.real_encode = enc
end

function M.load_mod(root, with_ui)
  local parts = { "items", "inventory", "ammo", "plan", "item_use", "ui_model", "ui_interaction",
    "loot", "deployables", "deploy_hud", "loadout", "gear", "carry" }
  if with_ui then parts[#parts + 1] = "ui_beardlib" end
  for _, n in ipairs(parts) do dofile(root .. "lua/" .. n .. ".lua") end
end

-- ---- a small fake of the parts of PAYDAY 2 the mod talks to ----
function M.install_game()
  _G.tweak_data = {
    weapon = {
      factory = { parts = {
        ["wpn_mag_test"] = { type = "magazine", stats = { CLIP_AMMO_MAX = 30, mag_amount = 3 } },
        ["wpn_mag_small"] = { type = "magazine", stats = { CLIP_AMMO_MAX = 20, mag_amount = 2 } }
      } },
      test_rifle = { AMMO_MAX = 90, categories = { "rifle" } },
      -- an untyped magazine weapon of the older tests (SMGs now have sizes and bullets)
      test_smg = { AMMO_MAX = 60, categories = { "lmg" } },
      test_ar = { AMMO_MAX = 150, CLIP_AMMO_MAX = 30, categories = { "assault_rifle" } },
      test_akimbo_smg = { AMMO_MAX = 120, CLIP_AMMO_MAX = 40, categories = { "akimbo", "smg" } },
      test_pistol = { AMMO_MAX = 60, categories = { "pistol" } },
      test_pump = { AMMO_MAX = 48, categories = { "shotgun" } },
      test_double = { AMMO_MAX = 30, categories = { "shotgun" } },
      test_gl = { AMMO_MAX = 6, categories = { "grenade_launcher" } },
      test_bow = { AMMO_MAX = 20, categories = { "bow" } },
      test_akimbo = { AMMO_MAX = 120, categories = { "akimbo", "pistol" } }
    },
    equipments = {
      ammo_bag = { action_timer = 1, icon = "equipment_ammo_bag", unit = "units/equipments/ammo_bag",
        dummy_unit = "units/equipments/ammo_bag", deploy_time = 0.5 },
      doctor_bag = { action_timer = 1, icon = "equipment_doctor_bag", unit = "units/equipments/doctor_bag",
        dummy_unit = "units/equipments/doctor_bag", deploy_time = 0.5 },
      first_aid_kit = { action_timer = 1, icon = "equipment_firstaid", unit = "units/equipments/first_aid_kit",
        dummy_unit = "units/equipments/first_aid_kit", deploy_time = 0.5 },
      bodybags_bag = { action_timer = 1, icon = "equipment_bodybags", unit = "units/equipments/bodybags_bag",
        dummy_unit = "units/equipments/bodybags_bag", deploy_time = 0.5 }
    },
    -- the carry data of the game: every bag that holds loot has a bag value
    carry = {
      gold = { type = "heavy", bag_value = "gold" },
      money = { type = "medium", bag_value = "money" },
      diamonds = { type = "light", bag_value = "diamonds" },
      person = { type = "being" },
      circuit = { type = "light" }
    }
  }

  _G.Application = {
    digest_value = function(_, value, digested)
      if digested then return { digested = true, value = value } end
      if type(value) == "table" and value.digested then return value.value end
      return value
    end
  }

  _G.PlayerStandard = {
    _get_input = function() return {} end,
    _check_action_reload = function() return false end,
    _interupt_action_reload = function() end,
    _update_equip_weapon_timers = function() end,
    _changing_weapon = function() return false end,
    _start_action_unequip_weapon = function() end,
    say_line = function() end
  }
  _G.NewRaycastWeaponBase = {
    -- like the game: a reload needs ammunition beyond the clip
    can_reload = function(self) return self:get_ammo_remaining_in_clip() < self:get_ammo_total() end,
    -- like the game (RaycastWeaponBase:on_reload): the clip becomes as full
    -- as the ammunition allows
    on_reload = function(self)
      self._reloaded = (self._reloaded or 0) + 1
      self:set_ammo_remaining_in_clip(math.min(self:get_ammo_total(), self:get_ammo_max_per_clip()))
    end,
    -- like the game: a shotgun loads one shell per call
    update_reloading = function(self)
      if not self._use_shotgun_reload then return end
      self:set_ammo_remaining_in_clip(math.min(self:get_ammo_max_per_clip(), self:get_ammo_remaining_in_clip() + 1))
      return true
    end,
    update_r_stage = function() end,
    drop_magazine_object = function() end,
    -- the game: skills make reloads faster
    reload_speed_multiplier = function() return 1 end
  }
  _G.RaycastWeaponBase = {
    add_ammo = function() return false, 0 end,
    -- like the game: the bag fills the weapon with its ammunition
    add_ammo_from_bag = function(self, available)
      self:set_ammo_total(self:get_ammo_total() + (tonumber(available) or 0))
    end
  }
  _G.PlayerInventory = { need_ammo = function() return false end }
  _G.HUDTeammate = { set_ammo_amount_by_type = function() end }

  _G.HUDManager = { PLAYER_PANEL = "player_panel" }
  _G.PlayerBase = { PLAYER_INFO_HUD_PD2 = "pd2" }
  _G.Vector3 = function() return { x = 0, y = 0, z = 0 } end
  _G.Rotation = function() return {} end
  _G.mvector3 = {
    set = function() end, multiply = function() end, add = function() end,
    subtract = function() end, normalize = function() end, dot = function() return 0 end,
    distance = function() return 0 end, length = function() return 0 end
  }
  _G.World = { raycast = function() return nil end }
  _G.alive = function(unit) return unit ~= nil end

  M.game = { weapons = {}, equipment = nil, body_bags = 0, carry_id = nil, thrown = {},
    registered = {}, state = "standard", cooldown = false }
  _G.Network = { is_client = function() return M.game.client == true end,
    is_server = function() return M.game.client ~= true end }
  local peer = {}
  function peer:verify_bag(carry_id, pickup)
    if pickup then M.game.registered[#M.game.registered + 1] = carry_id; return true end
    for i, id in ipairs(M.game.registered) do
      if id == carry_id then table.remove(M.game.registered, i) return true end
    end
    return false
  end
  M.game.peer = peer
  _G.CarryInteractionExt = setmetatable({
    _interact_blocked = function() return managers.player:is_carrying() end,
    can_select = function() return not managers.player:is_carrying() end,
    interact = function(self)
      managers.player:set_carry(self._carry_id, 1)
      managers.player:register_carry(M.game.peer, self._carry_id)
      return true
    end
  }, { __index = {} })
  CarryInteractionExt.super = { can_select = function() return true end }
  _G.managers = {
    player = {
      player_unit = function() return M.game.unit end,
      selected_equipment = function() return nil end,
      can_use_selected_equipment = function() return false end,
      use_selected_equipment = function() return nil end,
      get_body_bags_amount = function() return M.game.body_bags end,
      current_carry_id = function() return M.game.carry_id end,
      get_my_carry_data = function()
        if not M.game.carry_id then return nil end
        return { carry_id = M.game.carry_id, multiplier = M.game.carry_multiplier or 1 }
      end,
      is_carrying = function() return M.game.carry_id ~= nil end,
      set_carry = function(_, id, multiplier) M.game.carry_id = id; M.game.carry_multiplier = multiplier end,
      clear_carry = function() M.game.carry_id = nil end,
      drop_carry = function()
        if M.game.carry_id then
          M.game.thrown[#M.game.thrown + 1] = M.game.carry_id
          M.game.peer:verify_bag(M.game.carry_id, false)
          -- like the game: no bag can be picked up for 1.2-1.5 s after a throw
          M.game.cooldown = true
        end
        M.game.carry_id = nil
      end,
      register_carry = function(_, peer, id) return peer:verify_bag(id, true) end,
      carry_blocked_by_cooldown = function() return M.game.cooldown end,
      can_carry = function(_, id) return M.game.cannot_carry ~= id end,
      current_state = function() return M.game.state end
    },
    network = { session = function() return { local_peer = function() return M.game.peer end } end },
    hud = { set_ammo_amount = function() end },
    localization = { text = function(_, id) return id end, exists = function() return false end }
  }
  return M.game
end

-- A weapon that behaves like the ones of the game.
function M.make_weapon(name_id, blueprint, capacity, extra)
  local wep = {
    _name_id = name_id or "test_rifle",
    _blueprint = blueprint or { "wpn_mag_test" },
    _setup = { user_unit = M.game and M.game.unit },
    clip = 0, total = 0, ammo_max = 90
  }
  for k, v in pairs(extra or {}) do wep[k] = v end
  function wep:selection_index() return self._selection or 2 end
  function wep:get_ammo_remaining_in_clip() return self.clip end
  function wep:set_ammo_remaining_in_clip(v) self.clip = v end
  function wep:get_ammo_total() return self.total end
  function wep:set_ammo_total(v)
    self.total = v
    -- a bow: the arrow on the string is the arrows you carry
    if self._no_reload then self.clip = v end
  end
  function wep:get_ammo_max() return self.ammo_max end
  function wep:set_ammo_max(v) self.ammo_max = v end
  wep.max_clip = capacity or 30
  function wep:get_ammo_max_per_clip() return self.max_clip end
  function wep:set_ammo_max_per_clip(v) self.max_clip = v end
  function wep:get_chamber() return 0 end
  function wep:weapon_tweak_data() return tweak_data.weapon[self._name_id] end
  return wep
end

-- A player unit that owns a weapon and the equipment object.
function M.make_unit()
  local unit = {}
  function unit:key() return "player" end
  function unit:inventory() return self.inventory end
  function unit:equipment() return self.equipment end
  function unit:base() return self.weapon end
  function unit:set_weapon(wep) self.weapon = wep end
  local inventory = {}
  function inventory:available_selections()
    return { { unit = { base = function() return unit.weapon end } } }
  end
  function inventory:equipped_unit() return { base = function() return unit.weapon end } end
  -- the game calls the inventory as a method
  function unit:inventory() return inventory end
  unit.get_inventory = inventory
  M.game.unit = unit
  return unit
end

-- The equipment object of the game: the placement functions of the game.
function M.make_equipment(placed)
  local equipment = { placed = placed or {} }
  function equipment:valid_shape_placement(equipment_id, equipment_data)
    self.validated = { id = equipment_id, data = equipment_data }
    self.dummy_created = self.dummy_created or (equipment_data ~= nil)
    return { position = { x = 0, y = 0, z = 0 } }
  end
  for _, name in ipairs({ "use_ammo_bag", "use_doctor_bag", "use_first_aid_kit", "use_bodybags_bag" }) do
    equipment[name] = function(self)
      if self.dummy_created then
        self.placed[#self.placed + 1] = name
        return true
      end
      return false
    end
  end
  M.game.equipment = equipment
  return equipment
end


-- ---- fake MenuUI (documented parameters only) ----
local DOCUMENTED = {}
for _, k in ipairs({
  "name","text","help","on_callback","enabled","visible","label","position","index","on_right_click",
  "inherit_value","private","highlight","divider_type","ignore_align","count_as_aligned",
  "localized","items_localized","help_localized","size","offset","text_offset","font","font_size",
  "kerning","text_align","text_vertical","size_by_text","bg_callbacks","items","open_list_key",
  "searchbox","foreground","foreground_highlight","auto_foreground","background_color","full_bg_color",
  "unhighlight_color","highlight_color","accent_color","line_color","enabled_alpha","disabled_alpha",
  "control_slice","w","max_width","min_width","max_height","min_height","last_y_offset",
  "background_alpha","context_background_color","scroll_color","click_btn","range_color","alone_in_row",
  "animate_colors","border_color","border_visible","border_left","border_right","border_top",
  "border_bottom","border_lock_height","border_center_as_title","border_position_below_title",
  "border_size","border_width","border_height","delay_align_items","background_visible",
  "background_blur","auto_align","align_method","scrollbar","scroll_width","auto_height","closed",
  "texture","texture_rect","icon_w","icon_h","img_offset","img_offset_x","img_offset_y",
  "highlight_image","img_color"
}) do DOCUMENTED[k] = true end
M.violations = {}

local Item = {}
Item.__index = Item
local function new_item(kind, params, parent)
  for k in pairs(params or {}) do
    if not DOCUMENTED[k] then M.violations[#M.violations + 1] = kind .. ":" .. tostring(k) end
  end
  local it = setmetatable({ kind = kind, params = params or {}, children = {}, parent = parent }, Item)
  local p = it.params
  it.pw, it.ph = p.w or 100, p.size or 18
  return it
end
function Item:Panel()
  local it = self
  it.rects = it.rects or {}
  return {
    w = function() return it.pw end, h = function() return it.ph end,
    set_size = function(_, w, h) it.pw, it.ph = w, h end,
    -- drawn rectangles (the drag preview)
    rect = function(_, p) local r = { params = p }; it.rects[#it.rects + 1] = r; return r end,
    remove = function(_, r) for i, x in ipairs(it.rects) do if x == r then table.remove(it.rects, i) break end end end
  }
end
for _, kind in ipairs({ "Button", "Divider", "Menu", "Holder", "Group" }) do
  Item[kind] = function(self, params)
    local c = new_item(kind, params, self)
    self.children[#self.children + 1] = c
    self.dirty = true -- needs AlignItems before positions are real (auto_align=false)
    return c
  end
end
function Item:AlignItems() self.align_calls = (self.align_calls or 0) + 1; self.dirty = false end
function Item:ClearItems(label)
  local keep = {}
  for _, c in ipairs(self.children) do
    if label ~= nil and c.params.label ~= label then keep[#keep + 1] = c end
  end
  self.children = keep
end
function Item:SetSize(w, h) self.pw, self.ph = w, h end
function Item:find(name)
  for _, c in ipairs(self.children) do if c.params.name == name then return c end end
end
function Item:click()
  assert(self.params.on_callback, "no callback on " .. tostring(self.params.name))
  self.params.on_callback(self)
end

function M.install_menuui(defer)
  M.violations = {}
  M.menus = {}
  local MenuUI = {}
  MenuUI.__index = MenuUI
  function MenuUI:new(params)
    for _, k in ipairs({}) do end
    local m = setmetatable({ params = params, enabled = params.enabled == true,
      children = {}, Menu = Item.Menu, Holder = Item.Holder }, MenuUI)
    M.menus[#M.menus + 1] = m
    m.Menu = function(self2, p)
      local c = new_item("Menu", p, self2)
      self2.children[#self2.children + 1] = c
      return c
    end
    if params.create_items then
      if defer then m.pending = params.create_items else params.create_items(m) end
    end
    return m
  end
  function MenuUI:finish() if self.pending then self.pending(self); self.pending = nil end end
  function MenuUI:Enable() self.enabled = true end
  function MenuUI:Disable() self.enabled = false end
  function MenuUI:Enabled() return self.enabled end
  _G.MenuUI = MenuUI
  _G.Color = function(...) return { ... } end
  M.triggers = {}
  _G.BeardLib = { Utils = { Input = {
    Trigger = function(_, key, clbk) local t = { key = key, clbk = clbk }; M.triggers[#M.triggers + 1] = t; return t end,
    RemoveTrigger = function(_, t) for i, x in ipairs(M.triggers) do if x == t then table.remove(M.triggers, i) break end end end
  } } }
end

function M.remove_menuui()
  _G.MenuUI, _G.BeardLib, _G.Color = nil, nil, nil
end

return M
