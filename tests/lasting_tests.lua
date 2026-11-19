-- 0.48.0: lasting body damage (body_lasting.lua). The parts keep what a
-- heist left them; the next heist and the safehouse start so. Ended down or
-- in custody, or a heist left: every part at 0, the head at 1 HP. Dallas
-- (his room in the safehouse) and the menu's Health tab heal everything for
-- $15,000.
--   luajit tests/lasting_tests.lua
local script = arg and arg[0] or "tests/lasting_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_lasting") .. "/"
ENV.setup(ROOT, TMP)
_G.ModPath = ROOT
ENV.install_game()
ENV.load_mod(ROOT, true)
_G.Application = _G.Application or {}
Application.digest_value = function(_, v) return v end
Application.time = Application.time or function() return os.clock() end

-- The game's PlayerDamage (as body_tests.lua).
_G.PlayerDamage = {}
local PD = PlayerDamage
PD.__index = PD
function PD:_max_health() return self.max end
function PD:get_real_health() return self._health end
function PD:set_health(h) self._health = math.max(0, math.min(self.max, h)) end
function PD:change_health(d) self:set_health(self._health + d) end
function PD:need_revive() return self.downed end
function PD:_check_bleed_out() if self._health <= 0 then self.downed = true end end
function PD:_calc_health_damage(a) self:change_health(-a.damage); self:_check_bleed_out() end
function PD:_calc_armor_damage() end
function PD:damage_bullet(a) self:_calc_health_damage(a) end
function PD:damage_melee(a) self:damage_bullet(a) end
function PD:damage_fall(a) self:_calc_health_damage(a) end
function PD:damage_explosion(a) self:_calc_health_damage(a) end
function PD:band_aid_health() self:change_health(self:_max_health()) end
function PD:revive() self.downed = false; self:set_health(self.max * 0.4) end
function PD:_regenerated() self:set_health(self:_max_health()) end
function PD:recover_health() if self:need_revive() then self:revive(true) end self:_regenerated() end
function PD:replenish() self:recover_health() end
_G.PlayerMovement = { _max_stamina = function() return 50 end }
PlayerStandard._start_action_running = function() end
PlayerStandard._check_action_run = function() end
NewRaycastWeaponBase.recoil_multiplier = function() return 1 end
NewRaycastWeaponBase.spread_multiplier = function() return 1 end

dofile(ROOT .. "lua/body.lua")
dofile(ROOT .. "lua/body_lasting.lua")
local Body, L, Home = PDTI.Body, PDTI.BodyLasting, PDTI.Safehouse

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b, eps) return math.abs((a or -999) - b) < (eps or 1e-6) end
local function logged(text)
  for _, l in ipairs(ENV.logs) do if tostring(l):find(text, 1, true) then return true end end
  return false
end
T("the body's hooks are in place", Body.InstallHooks() == true)

local money = 100000
managers.money = {
  total = function() return money end,
  deduct_from_total = function(_, v) money = money - v end,
  add_to_total = function(_, v) money = money + v end
}
local job = nil
managers.job = { current_job_id = function() return job end }
local hints = {}
PDTI.Hint = function(t) hints[#hints + 1] = t end
local Money = PDTI.Ammo.Money

-- Max health 44: head 3.5, body 15.5, arms 6, legs 6.5 (body_tests.lua).
local rolls = {}
Body.roll = function() return table.remove(rolls, 1) or 0.5 end
local ROLL = { head = 0.03, body = 0.3, arm_l = 0.5, arm_r = 0.6, leg_l = 0.75, leg_r = 0.9 }
local function shoot(pd, part, dmg) rolls = { ROLL[part] }; pd:damage_bullet({ damage = dmg }) end
local state_name = "standard"
local function spawn()
  local pd = setmetatable({ max = 44, _health = 44, armor = 0, downed = false }, PD)
  local unit = { character_damage = function() return pd end }
  managers.player = { player_unit = function() return unit end, current_state = function() return state_name end }
  Body.AttachPlayer()
  return pd
end
-- A heist level starts (gamesetup: Body first, then this).
local function heist_start()
  job = "firestarter_1"
  PDTI.session_only = true
  Body.OnHeistStart()
  L.OnLevelStart()
  state_name = "standard"
  return spawn()
end
local function heist_end(how)
  if how == "custody" then managers.player = { player_unit = function() return nil end } end
  if how == "downed" then state_name = "bleed_out" end
  L.OnMissionEnd()
end
local function to_menu()
  managers.player = nil
  PDTI.session_only = false
  job = nil
  L.Reset()
  L.OnMenu()
end
local function fresh()
  os.remove(TMP .. L.FileName(1))
  L.Reset()
  Body.state.owner = nil
  Body.start_frac = nil
  Body.RestoreAll()
  money, hints, state_name, job = 100000, {}, "standard", nil
  PDTI.session_only = false
end
local function frac(id) return L.Parts()[id] end

------------------------------------------------------------ carried

do
  fresh()
  T("a new save: every part full, not hurt", not L.Hurt() and frac("head") == 1 and frac("leg_l") == 1 and L.Summary() == nil)
  local pd = heist_start()
  T("  the heist starts full", near(pd._health, 44))
  shoot(pd, "leg_l", 10) -- black, 3.5 over at 75% to the body
  shoot(pd, "arm_r", 3)
  T("the end is saved", L.OnMissionEnd() == true)
  T("standing at the end: the parts are kept", frac("leg_l") == 0 and near(frac("arm_r"), 0.5)
    and near(frac("body"), (15.5 - 2.625) / 15.5) and frac("head") == 1)
  T("  logged", logged("the heist ended: the parts are kept"))
  to_menu()
  T("at the menu: hurt, the screen's parts are the saved ones", L.Hurt() and Body.IsBlack("leg_l")
    and near(Body.Frac("arm_r"), 0.5) and Body.state.owner == nil)
  T("  the summary", L.Summary() == "Body 83%, Right arm 50%, Left leg 0% (black)", L.Summary())
  pd = heist_start()
  T("the next heist starts with them: the black leg stays black", Body.IsBlack("leg_l") and near(Body.HP("arm_r"), 3))
  T("  the game's health is their sum", near(pd._health, Body.Sum()) and pd._health < 44, pd._health)
  -- Custody inside the heist: back fresh.
  local back = spawn()
  T("back from custody in the heist: a fresh body", near(back._health, 44) and not Body.IsBlack("leg_l"))
  heist_end()
  to_menu()
  T("  and ended standing so: full again", not L.Hurt())
end

do
  fresh()
  local pd = heist_start()
  shoot(pd, "arm_l", 2)
  heist_end("custody")
  to_menu()
  local head = L.Parts().head
  T("ended in custody: every part at 0", frac("body") == 0 and frac("arm_l") == 0 and frac("arm_r") == 0
    and frac("leg_l") == 0 and frac("leg_r") == 0)
  T("  the head at 1 HP", near(head * 3.5, 0.1), head)
  T("  logged", logged("the heist ended down"))
  pd = heist_start()
  T("  the next heist starts so (1 HP on the screen)", near(pd._health, 0.1) and Body.IsBlack("body")
    and not Body.IsBlack("head"), pd._health)
  heist_end()
  fresh()
  heist_start()
  heist_end("downed")
  to_menu()
  T("ended downed (bleeding out), unhurt: every part at 0, the head at 1 HP", frac("body") == 0
    and frac("leg_l") == 0 and near(frac("head") * 3.5, 0.1))
  fresh()
  pd = heist_start()
  shoot(pd, "head", 5)
  state_name = "standard"
  heist_end()
  to_menu()
  T("a black head at the end counts as down", frac("leg_r") == 0 and near(frac("head") * 3.5, 0.1))
end

do
  fresh()
  heist_start()
  T("in a heist the file says so", L._Data().in_heist == true)
  L.Reset()
  T("  (written)", L._Data().in_heist == true)
  to_menu()
  L.Reset()
  T("a heist left (no end): every part at 0, the head at 1 HP (written)", frac("body") == 0
    and near(frac("head") * 3.5, 0.1) and L._Data().in_heist == false)
  T("  logged", logged("a heist was left"))
  -- The next day of a heist: it goes on.
  fresh()
  local pd = heist_start()
  shoot(pd, "arm_r", 3)
  heist_end()
  pd = heist_start()
  T("the next day of a heist starts as the last ended", near(Body.HP("arm_r"), 3))
  -- The head never starts below 1 HP.
  local d = L._Data()
  d.frac.head = 0
  L.Save()
  L.Reset()
  Body.OnHeistStart(); L.OnLevelStart(); spawn()
  T("a saved black head starts at 1 HP", near(Body.HP("head"), 0.1))
end

do
  fresh()
  -- Frenzy: a part a skill wants black still starts black.
  Body.mods.start_black = function(id) return id == "arm_l" end
  local d = L._Data()
  d.frac.arm_r = 0.5
  heist_start()
  T("with a skill's black part: both", Body.IsBlack("arm_l") and near(Body.HP("arm_r"), 3))
  Body.mods.start_black = nil
end

------------------------------------------------------------ the safehouse

do
  fresh()
  local d = L._Data()
  d.frac.leg_l = 0
  L.Save()
  job = "chill"
  T("a level starts", L.OnLevelStart() == true)
  local pd = spawn()
  T("the safehouse shows the damage", Body.IsBlack("leg_l") and pd._health < 44)
  T("  the screen never overwrites a live body", Body.ShowParts({}) == false and Body.IsBlack("leg_l"))
  T("  and is not a heist (not marked)", L._Data().in_heist == false)
  shoot(pd, "arm_r", 3)
  T("  its end saves nothing", L.OnMissionEnd() == false and frac("arm_r") == 1)
  -- Dallas.
  tweak_data.safehouse = { rooms = { { room_id = "russian", name_id = "menu_russian", tier_max = 3 },
    { room_id = "german", name_id = "menu_german", tier_max = 3 } } }
  managers.custom_safehouse = {
    get_room_current_tier = function() return 3 end, get_room_max_tier = function() return 3 end,
    get_next_tier_unlocked = function() return 4 end, get_upgrade_cost = function() return 0 end,
    can_afford_room_tier = function() return false end, coins = function() return 0 end,
    purchase_room_tier = function() end, set_room_tier = function() end
  }
  managers.localization = managers.localization or { text = function(_, id) return id end }
  local dialogs = {}
  managers.system_menu = { is_active = function() return false end, show = function(_, x) dialogs[#dialogs + 1] = x end }
  local function button(x, prefix)
    for _, b in ipairs(x.button_list) do if b.text:sub(1, #prefix) == prefix then return b end end
  end
  T("Dallas's menu opens", Home.ShowRoomMenu("russian") == true)
  local m = dialogs[#dialogs]
  local heal = button(m, "Heal everything")
  T("  Heal everything ($15,000)", heal ~= nil and heal.text == "Heal everything (" .. Money(15000) .. ")")
  T("  it says what is hurt", m.text:find("Hurt: Left leg 0% (black)", 1, true) ~= nil, m.text)
  Home.ShowRoomMenu("german")
  T("  not in another room", button(dialogs[#dialogs], "Heal") == nil)
  heal.callback_func()
  T("healed in the safehouse: paid, every part full, your character too", money == 85000 and not L.Hurt()
    and not Body.IsBlack("leg_l") and near(pd._health, 44) and hints[#hints] == "Healed everything for " .. Money(15000))
  T("  written", (function() L.Reset(); return not L.Hurt() end)())
  Home.ShowRoomMenu("russian")
  T("not hurt: no Heal button", button(dialogs[#dialogs], "Heal") == nil)
  T("  HealAll says so", select(2, L.HealAll()) == "You are not hurt" and money == 85000)
  L._Data().frac.body = 0.2
  money = 100
  T("not enough money: said, nothing healed", select(2, L.HealAll()) == "Not enough money (" .. Money(15000) .. ")"
    and L.Hurt())
  money = 100000
  job = "firestarter_1"
  PDTI.session_only = true
  T("in a heist: no heal", select(2, L.HealAll()) == "In a heist, heal with a first aid kit or a medic bag" and L.Hurt())
  PDTI.session_only = false
  job = nil
end

------------------------------------------------------------ the file

do
  local d = L._Sanitize({ frac = { head = 2, body = -1, arm_l = "x", leg_l = 0 / 0, leg_r = 0.25 }, in_heist = true })
  T("the file: clamped, nonsense full", d.frac.head == 1 and d.frac.body == 0 and d.frac.arm_l == 1
    and d.frac.leg_l == 1 and d.frac.leg_r == 0.25 and d.frac.arm_r == 1 and d.in_heist == true)
  T("  nothing: full, not in a heist", L._Sanitize(nil).frac.head == 1 and L._Sanitize(nil).in_heist == false
    and L._Sanitize({ frac = 5 }).frac.body == 1)
  local sep = PDTI.SeparateSave
  PDTI.SeparateSave = function() return true end
  T("its name: the mod's own save", L.FileName(2) == "pdti_save_body_profile2.json")
  PDTI.SeparateSave = function() return false end
  T("  or the old style", L.FileName(1) == "pdti_body.json" and L.FileName(3) == "pdti_body_profile3.json")
  PDTI.SeparateSave = sep
end

------------------------------------------------------------ off

do
  fresh()
  PDTI.Ammo.settings.body_parts = false
  T("health per body part off: nothing", L.OnLevelStart() == false and L.OnMissionEnd() == false and L.OnMenu() == false
    and select(2, L.HealAll()) == "Health per body part is off")
  PDTI.Ammo.settings.body_parts = nil
end

------------------------------------------------------------ the menu screen

do
  fresh()
  managers.player = nil
  L._Data().frac.leg_r = 0
  L.Save()
  L.OnMenu()
  ENV.install_menuui(false)
  local function windows() return ENV.menus[#ENV.menus].children end
  local function named(n) for _, w in ipairs(windows()) do if w.params.name == n then return w end end end
  T("the screen opens", PDTI.ToggleUI() == true)
  local shop = named("pdti_shop")
  T("the Health tab, marked hurt", shop:find("shop_tab_health") ~= nil
    and shop:find("shop_tab_health").params.text == "Health (hurt)")
  shop:find("shop_tab_health"):click()
  shop = named("pdti_shop")
  T("  the figure: the right leg black", shop:find("health_part_leg_r") ~= nil
    and shop:find("health_part_leg_r").params.text:find("0 /", 1, true) ~= nil)
  T("  the Heal button", shop:find("health_heal") ~= nil
    and shop:find("health_heal").params.text == "Heal everything (" .. Money(15000) .. ")")
  T("  fits 720p", shop.ph <= 720, shop.ph)
  T("  the button under the figure", shop:find("health_heal").params.position[2]
    > shop:find("health_part_leg_r").params.position[2] + 20)
  T("  damage stays: said", shop:find("health_lasting") ~= nil)
  T("the menu shows the saved parts", L.OnMenu() == true)
  T("  no health window of its own at home", named("pdti_health") == nil or named("pdti_health").pw <= 1)
  shop:find("health_heal"):click()
  shop = named("pdti_shop")
  T("  a click heals: paid, said, the leg full", money == 85000 and not L.Hurt() and not Body.IsBlack("leg_r")
    and shop:find("health_status").params.text == "Healed everything for " .. Money(15000))
  T("  now: not hurt, no button", shop:find("health_heal") == nil and shop:find("health_fine") ~= nil
    and shop:find("shop_tab_health").params.text == "Health")
  PDTI.SetUIOpen(false)
  T("only documented MenuUI parameters used", #ENV.violations == 0, table.concat(ENV.violations, ","))
end

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
