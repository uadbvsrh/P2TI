-- 0.26.0: Ghost: Shinobi (Cleaner ace, ECM Specialist basic) and Artful
-- Dodger (Inner Pockets ace, Sneaky Bastard) (SKILLS_REWORK_SPEC.md §7.1, §7.2).
--   luajit tests/ghost_skills_tests.lua
local script = arg and arg[0] or "tests/ghost_skills_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_ghost") .. "/")
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.load_mod(ROOT, false)
PDTI._loaded = true

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b, eps) return math.abs((a or -999) - b) < (eps or 1e-6) end

---------------------------------------------------------------- the game

local owned = {}
_G.PlayerManager = {}
function PlayerManager:upgrade_value(cat, up, default)
  local v = owned[cat .. "." .. up]
  if v == nil then return default or 0 end
  return v
end
function PlayerManager:has_category_upgrade(cat, up) return owned[cat .. "." .. up] ~= nil end
function PlayerManager:upgrade_level() return 0 end
-- The game's dodge: the armour's and the concealment upgrade's.
function PlayerManager:skill_dodge_chance(running, crouching, zipline, armor, risk)
  return 0.05 + self:upgrade_value("player", "detection_risk_add_dodge_chance", 0)
end
local speed = 0
local unit = {
  movement = function() return { current_state = function()
    return { _last_velocity_xy = { length = function() return speed end } }
  end } end
}
local pm = managers.player
setmetatable(pm, { __index = PlayerManager })
pm.player_unit = function() return unit end
local hints = {}
managers.hud = managers.hud or {}
managers.hud.show_hint = function(_, h) hints[#hints + 1] = h.text end

_G.tweak_data = _G.tweak_data or {}
tweak_data.player = { movement_state = { standard = { movement = { speed = { RUNNING_MAX = 575, STANDARD_MAX = 350 } } } } }

-- Carrying: the game blocks running with a body and walks at 50%.
local ran = 0
local Base = {}
function Base:_check_action_run() ran = ran + 1 end
function Base:_get_max_walk_speed() return self._running and 575 or 350 end
_G.PlayerCarry = setmetatable({}, { __index = Base })
PlayerCarry.super = Base
function PlayerCarry:_check_action_run(...)
  if self._tweak_data_name ~= "being" then Base._check_action_run(self, ...) end
end
function PlayerCarry:_get_max_walk_speed(...)
  return Base._get_max_walk_speed(self, ...) * (self._tweak_data_name == "being" and 0.5 or 1)
end

dofile(ROOT .. "lua/skills.lua")
dofile(ROOT .. "lua/skills_ghost.lua")
local Skills, G = PDTI.Skills, PDTI.GhostSkills
local steps = {}
local known = true
Skills.step_of = function(id) return steps[id] or 0 end
Skills.known = function() return known end
local function own(list) steps = {}; for id, s in pairs(list or {}) do steps[id] = s end; G.ApplyItems() end

T("the skill hooks are in place", Skills.Install() == true)

local function pockets() return PDTI.GetContainerInfo("pockets") end

------------------------------------------------------------ Cleaner

own({})
T("no skill: the body bag case is 2x2", PDTI.items.bodybags_bag.w == 2 and PDTI.items.bodybags_bag.h == 2)
own({ cleaner = 1 })
T("basic: still 2x2", PDTI.items.bodybags_bag.h == 2)
own({ cleaner = 2 })
T("ace: 2x1 (2 cells)", PDTI.items.bodybags_bag.w == 2 and PDTI.items.bodybags_bag.h == 1)
PDTI.Deployables.enabled = false
G.ApplyItems()
T("deployables off: 2x2", PDTI.items.bodybags_bag.h == 2)
PDTI.Deployables.enabled = true

local body = setmetatable({ _tweak_data_name = "being" }, { __index = PlayerCarry })
local bag = setmetatable({ _tweak_data_name = "heavy" }, { __index = PlayerCarry })
own({})
ran = 0
PlayerCarry._check_action_run(body)
T("no skill: no running with a body", ran == 0)
own({ cleaner = 2 })
PlayerCarry._check_action_run(body)
T("ace: you can run with a body", ran == 1)
body._running = true
T("ace: at 70% of the run speed", near(PlayerCarry._get_max_walk_speed(body), 575 * 0.7))
body._running = false
T("walking with a body stays 50%", near(PlayerCarry._get_max_walk_speed(body), 175))
bag._running = true
T("other bags as the game has them", near(PlayerCarry._get_max_walk_speed(bag), 575))
own({ cleaner = 1 })
body._running = true
T("basic: the game's speed", near(PlayerCarry._get_max_walk_speed(body), 287.5))
body._running = false

------------------------------------------------------- ECM Specialist

own({})
T("no skill: 1 ECM to a cell", PDTI.items.ecm_jammer.max_stack == 1)
own({ ecm_2x = 1 })
T("basic: 2 to a cell", PDTI.items.ecm_jammer.max_stack == 2)
PDTI.Reset()
T("two ECMs go in one stack", PDTI.AddItem("backpack", "ecm_jammer", 0, 0, false, 2) == true)
PDTI.Deployables.enabled = false
G.ApplyItems()
T("deployables off: 1", PDTI.items.ecm_jammer.max_stack == 1)
PDTI.Deployables.enabled = true
own({})
G.Tidy()
local ecms = PDTI.FindItems(function(_, it) return it.item_id == "ecm_jammer" end)
T("the skill gone: the stack of 2 is split", #ecms == 2 and ecms[1].item.amount == 1 and ecms[2].item.amount == 1, #ecms)

-------------------------------------------------------- Inner Pockets

PDTI.Reset()
own({})
T("no skill: pockets 2x2, 4 kg", pockets().width == 2 and pockets().height == 2 and pockets().weight_limit == 4)
own({ thick_skin = 1 })
T("basic: as they are", pockets().height == 2)
own({ thick_skin = 2 })
T("ace: a third row (+2 cells), 6 kg", pockets().width == 2 and pockets().height == 3 and pockets().weight_limit == 6)
known = false
own({})
T("skills not known yet: big, so a save is not cut", pockets().height == 3)
T("skills not known yet: ECMs stack 2, the body bag case is small", PDTI.items.ecm_jammer.max_stack == 2
  and PDTI.items.bodybags_bag.h == 1)
known = true
own({ thick_skin = 2 })
T("an item fits in the third row", PDTI.AddItem("pockets", "bandage", 1, 2, false, 1) == true)
own({})
T("without the ace it no longer fits", pockets().height == 2)
G.Tidy()
local where = PDTI.FindItems(function(_, it) return it.item_id == "bandage" end)[1]
T("tidy moves it where it fits", where and where.container ~= "pockets" or (where and where.item.y < 2),
  where and where.container)
-- A body bag case grown back.
PDTI.Reset()
own({ cleaner = 2 })
PDTI.AddItem("pockets", "bodybags_bag", 0, 0, false, 1)
PDTI.AddItem("pockets", "bandage", 0, 1, false, 1)
own({})
G.Tidy()
local case = PDTI.FindItems(function(_, it) return it.item_id == "bodybags_bag" end)[1]
T("a body bag case grown back to 2x2 is moved", case and case.container ~= "pockets", case and case.container)
T("nothing overlaps after the tidy", (function()
  for _, e in ipairs(PDTI.FindItems(function() return true end)) do
    local it = e.item
    if not PDTI.CanPlace(e.container, it, it.x, it.y, it.rotated == true, it.instance_id) then return false end
  end
  return true
end)())

------------------------------------------------------- Sneaky Bastard

owned["player.detection_risk_add_dodge_chance"] = 0.1
own({})
speed = 575
T("no skill: the game's dodge (concealment)", near(pm:skill_dodge_chance(true, false, false), 0.15))
own({ jail_diet = 1 })
speed = 0
T("standing still: no skill dodge", near(pm:skill_dodge_chance(false, false, false), 0.05))
speed = 287.5
T("half the sprint speed: 5%", near(pm:skill_dodge_chance(false, false, false), 0.10))
speed = 575
T("sprinting: 10%", near(pm:skill_dodge_chance(true, false, false), 0.15))
speed = 900
T("no cap: faster than a sprint, more dodge", near(pm:skill_dodge_chance(true, false, false), 0.05 + 0.1 * 900 / 575))
speed = 2300
T("no cap: 4x the sprint speed, 40%", near(G.VelocityDodge(), 0.40))
speed = 0 / 0
T("a broken speed reading: nothing", G.VelocityDodge() == 0)
speed = math.huge
T("an infinite speed reading: nothing", G.VelocityDodge() == 0)
speed = 350
T("basic at run speed: below the max", near(G.VelocityDodge(), 0.1 * 350 / 575))
own({ jail_diet = 2 })
T("ace: 10% at run speed", near(G.VelocityDodge(), 0.10))
speed = 575
T("ace: above 10% when sprinting", near(G.VelocityDodge(), 0.1 * 575 / 350))
speed = 350
speed = 175
T("ace: 5% at half the run speed", near(G.VelocityDodge(), 0.05))
T("the concealment dodge is off", pm:upgrade_value("player", "detection_risk_add_dodge_chance", 0) == 0)
T("the menu's stats (a risk given): no speed part", near(pm:skill_dodge_chance(false, false, false, nil, 10), 0.05))
PDTI.Carry.enabled = false
T("weight off: the vanilla skill", near(pm:skill_dodge_chance(false, false, false), 0.15))
PDTI.Carry.enabled = true
_G.restoration = {}
own({ jail_diet = 2, cleaner = 2, ecm_2x = 2, thick_skin = 2 })
T("restoration-mod: vanilla", near(pm:skill_dodge_chance(false, false, false), 0.15)
  and PDTI.items.bodybags_bag.h == 2 and PDTI.items.ecm_jammer.max_stack == 1 and pockets().height == 2)
_G.restoration = nil
own({})
owned = {}

T("every skill has its text", Skills.texts.menu_cleaner_beta_desc and Skills.texts.menu_ecm_2x_beta_desc
  and Skills.texts.menu_thick_skin_beta_desc and Skills.texts.menu_jail_diet_beta_desc and true)

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
