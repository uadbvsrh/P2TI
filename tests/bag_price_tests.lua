-- 0.18.5: an ammo bag restocks magazines (their own bullets, then new full
-- ones of the kind chosen in the menu); ammo boxes give standard rounds
-- only. 0.18.7: everything in the menu plan costs money, paid when it is
-- added and paid back when it is taken out; what a heist uses up is paid
-- again (the restock).
--   luajit tests/bag_price_tests.lua
local script = arg and arg[0] or "tests/bag_price_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_bag_price") .. "/")
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.install_menuui(false)
ENV.load_mod(ROOT, true)
PDTI._loaded = true
_G.Idstring = function(s) return "ids:" .. tostring(s) end
NewRaycastWeaponBase._get_current_damage = function(self, m) return 10 * (m or 1) end
_G.CopDamage = { roll_critical_hit = function(_, a) return false, a.damage end }
dofile(ROOT .. "lua/ammo_hooks.lua")
_G.Color = _G.Color or setmetatable({}, { __call = function(_, ...) return { ... } end })

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b) return math.abs((a or -99) - b) < 1e-6 end

local Ammo, Plan = PDTI.Ammo, PDTI.Plan
Ammo.InstallHooks()

-- An assault rifle (base magazine 30) in a heist.
local function rifle()
  PDTI.Reset()
  Ammo.Reset()
  Ammo.OnHeistStart()
  PDTI.SetEquipment("rig", "general_rig")
  PDTI.SetEquipment("backpack", "large_backpack")
  PDTI.SetSessionOnly(true)
  local unit = ENV.make_unit()
  local wep = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30)
  function wep:selection_index() return 2 end
  unit:set_weapon(wep)
  Ammo.EnsureSupply(wep)
  local info = Ammo.Identify(wep)
  for _, m in ipairs(Ammo.AllMagazines(info.key)) do PDTI.RemoveItem(m.container, m.instance_id) end
  return wep, info, unit
end
local function mags(key, fn)
  local out = {}
  for _, m in ipairs(Ammo.Magazines(key)) do if not fn or fn(m) then out[#out + 1] = m end end
  return out
end
local function special(key)
  local n = Ammo.LooseOfKey(key, "ap") + Ammo.LooseOfKey(key, "hollow")
  for _, m in ipairs(Ammo.AllMagazines(key)) do
    for _, part in ipairs(m.load or {}) do if part[1] ~= "standard" then n = n + part[2] end end
  end
  return n
end

----------------------------------------------------------- ammo boxes

do
  local wep, info = rifle()
  Ammo.AddLooseKey(info.key, 5, info, "hollow")
  Ammo.AddMagazineKey(info.key, 10, info, nil, { size = "standard", bullet = "ap" })
  local before = special(info.key)
  wep._ammo_pickup = { 20, 20 }
  local ok, n = RaycastWeaponBase.add_ammo(wep, 1)
  T("an ammo box is picked up", ok == true and n == 20, n)
  T("it gives standard rounds only", Ammo.LooseOfKey(info.key, "standard") == 20
    and special(info.key) == before, special(info.key) .. " vs " .. before)
  -- Holding R loads them: an armour-piercing magazine gets standard rounds
  -- on top, and no AP round is made.
  Ammo.StartJob(wep)
  for _ = 1, 40 do Ammo.Tick(1) end
  local ap = mags(info.key, function(m) return m.size == "standard" end)[1]
  T("standard rounds loaded on top of armour piercing stay standard", ap and ap.rounds == 30
    and Ammo.LoadString(ap.load) == "standard:20,ap:10", ap and Ammo.LoadString(ap.load))
  T("no armour-piercing or hollow-point round came out of a box", special(info.key) == before, special(info.key))
end

------------------------------------------------------------- ammo bags

do
  local wep, info = rifle()
  -- The menu chose compact magazines of 20 armour-piercing rounds.
  PDTI.SetPlanSlot("primary", "pick_size", "compact")
  PDTI.SetPlanSlot("primary", "pick_bullet", "ap")
  PDTI.SetPlanSlot("primary", "pick_load", "ap:20")
  Ammo.AddMagazineKey(info.key, 10, info, nil, { size = "standard", bullet = "ap" })
  Ammo.AddMagazineKey(info.key, 0, info, nil, { size = "extended", bullet = "hollow" })
  Ammo.AddMagazineKey(info.key, 15, info, nil, { size = "standard", load = "standard:5,ap:10" })
  Ammo.AddLooseKey(info.key, 7, info, "standard")
  local limit = Ammo.MaxMagCount(wep)
  -- A full bag (the game counts it in shares of a weapon's max ammunition).
  local used = RaycastWeaponBase.add_ammo_from_bag(wep, 4)
  local ap = mags(info.key, function(m) return m.size == "standard" and m.load and #m.load == 1 end)[1]
  T("a half-empty AP magazine comes back full of AP", ap and ap.rounds == 30 and Ammo.LoadString(ap.load) == "ap:30",
    ap and Ammo.LoadString(ap.load))
  local hp = mags(info.key, function(m) return m.size == "extended" end)[1]
  T("an empty hollow-point magazine comes back full of hollow points", hp and hp.rounds == 45
    and Ammo.LoadString(hp.load) == "hollow:45", hp and Ammo.LoadString(hp.load))
  local mixed = mags(info.key, function(m) return m.load and #m.load == 2 end)[1]
  T("a mixed magazine is topped up with the bullets on top", mixed and mixed.rounds == 30
    and Ammo.LoadString(mixed.load) == "standard:20,ap:10", mixed and Ammo.LoadString(mixed.load))
  local new = mags(info.key, function(m) return m.size == "compact" end)
  T("new full magazines of the kind chosen in the menu, up to what you may carry",
    #new == limit - 3 and #new > 0 and new[1].rounds == 20 and Ammo.LoadString(new[1].load) == "ap:20",
    #new .. " of " .. limit)
  T("the bag gives no loose rounds", Ammo.LooseOfKey(info.key) == 7, Ammo.LooseOfKey(info.key))
  local given = 20 + 45 + 15 + 20 * #new
  T("the bag is used by what it gave", near(used, given / wep:get_ammo_max()), used)
  T("a full stock needs no bag", Ammo.BagWanted(wep) == false)
  local again = RaycastWeaponBase.add_ammo_from_bag(wep, 4)
  T("and takes nothing from it", again == 0, again)
end

do -- A bag that is nearly empty: what it has, no magazine out of nothing.
  local wep, info = rifle()
  Ammo.AddMagazineKey(info.key, 0, info, nil, { size = "standard", bullet = "ap" })
  local share = 15 / wep:get_ammo_max() -- 15 rounds left in the bag
  local used = RaycastWeaponBase.add_ammo_from_bag(wep, share)
  local m = mags(info.key)
  T("a nearly empty bag fills what it can", m[1].rounds == 15 and near(used, share), m[1].rounds)
  T("and adds no magazine it cannot fill", #m == 1, #m)
end

do -- A weapon without sizes and bullets: full magazines, no load.
  PDTI.Reset()
  Ammo.Reset()
  Ammo.OnHeistStart()
  PDTI.SetSessionOnly(true)
  local unit = ENV.make_unit()
  local lmg = ENV.make_weapon("test_smg", { "wpn_mag_small" })
  function lmg:selection_index() return 2 end
  unit:set_weapon(lmg)
  Ammo.EnsureSupply(lmg)
  local info = Ammo.Identify(lmg)
  local first = Ammo.Magazines(info.key)[1]
  Ammo.SetMagazineRounds(first.container, first.instance_id, 3)
  RaycastWeaponBase.add_ammo_from_bag(lmg, 1)
  local all_full = true
  for _, m in ipairs(Ammo.Magazines(info.key)) do if m.rounds ~= info.capacity then all_full = false end end
  T("other weapons: every magazine full", all_full)
  T("as many as they may carry", #Ammo.Magazines(info.key) == Ammo.MaxMagCount(lmg), #Ammo.Magazines(info.key))
end

------------------------------------------------------------- the prices

T("normal rounds are the cheapest, armour piercing the dearest",
  Ammo.RoundPrice("standard") < Ammo.RoundPrice("hollow") and Ammo.RoundPrice("hollow") < Ammo.RoundPrice("ap"))
local function mag_price(size, bullet)
  local cap = Ammo.SpecCapacity(30, size)
  return Ammo.MagazinePrice({ size = size, rounds = cap, bullet = bullet, load = bullet .. ":" .. cap })
end
T("bigger magazines cost more: compact < standard < extended < drum",
  mag_price("compact", "standard") < mag_price("standard", "standard")
  and mag_price("standard", "standard") < mag_price("extended", "standard")
  and mag_price("extended", "standard") < mag_price("drum", "standard"))
T("an empty magazine costs its case", Ammo.MagazinePrice({ size = "drum", rounds = 0, bullet = "ap" })
  == Ammo.PRICES.magazine.drum)
T("the same magazine costs more with better bullets",
  mag_price("standard", "standard") < mag_price("standard", "hollow")
  and mag_price("standard", "hollow") < mag_price("standard", "ap"))
T("a mixed magazine: each round its price", Ammo.MagazinePrice({ size = "standard", rounds = 30,
  load = "ap:10,standard:20" }) == Ammo.PRICES.magazine.standard + 10 * Ammo.RoundPrice("ap") + 20 * Ammo.RoundPrice("standard"))
T("money reads like the game's", Ammo.Money(1234567) == "$1,234,567" and Ammo.Money(900) == "$900")

-- The menu plan.
local menu_weapons = { primary = { weapon_id = "test_ar", blueprint = { "wpn_no_part" } },
  secondary = { weapon_id = "test_pistol", blueprint = { "wpn_no_part" } } }
_G.managers.blackmarket = {
  equipped_primary = function() return menu_weapons.primary end,
  equipped_secondary = function() return menu_weapons.secondary end
}
tweak_data.weapon.test_pistol.CLIP_AMMO_MAX = 15
local money = { cash = 1000000, spent = 0 }
_G.managers.money = {
  total = function() return money.cash end,
  deduct_from_total = function(_, n) n = math.min(n, money.cash); money.cash = money.cash - n; money.spent = money.spent + n end,
  add_to_spending = function(_, n) money.cash = money.cash + n; money.back = (money.back or 0) + n end
}

PDTI.Reset()
Ammo.Reset()
PDTI.SetSessionOnly(false)
ENV.game.unit = nil
Plan.Refresh()
local base = Plan.Cost()
T("the plan has a price", base > 0, base)
Plan.SetSpec("primary", "pick_size", "drum")
Plan.SetPickCount("primary", "standard", 0)
Plan.SetPickCount("primary", "ap", 75)
local price = Plan.AddPrice("mag:primary")
T("a drum of armour piercing costs its case and 75 AP rounds",
  price == Ammo.PRICES.magazine.drum + 75 * Ammo.RoundPrice("ap"), price)
money.spent = 0
local paid_before = PDTI.PlanPaid()
Plan.Add("mag:primary")
T("adding it raises the plan's worth by that", Plan.Cost() == base + price, Plan.Cost())
T("and pays for it at once, from the spending cash", money.spent == price, money.spent)
T("the save knows what was paid", PDTI.PlanPaid() == paid_before + price, PDTI.PlanPaid())
T("loose rounds by the magazine", Plan.AddPrice("loose:primary:hollow") == 30 * Ammo.RoundPrice("hollow"))
money.cash, money.spent = price - 1, 0
local n = #Plan.Magazines("primary")
local ok, why = Plan.Add("mag:primary")
T("not enough money: nothing is added", ok == false and #Plan.Magazines("primary") == n
  and tostring(why):find("Not enough money") ~= nil, why)
T("and nothing is paid", money.spent == 0 and money.cash == price - 1)
money.cash = price
T("just enough: it is added", Plan.Add("mag:primary") == true and money.cash == 0, money.cash)

-- Taking out pays back.
money.cash, money.back = 0, 0
local paid = PDTI.PlanPaid()
T("taking a magazine out pays it back", Plan.Remove("mag:primary") == true and money.cash == price, money.cash)
T("and the save knows", PDTI.PlanPaid() == paid - price)
money.cash, money.spent = 1000000, 0
Plan.Add("loose:primary:hollow")
local hollow = 30 * Ammo.RoundPrice("hollow")
T("loose rounds are paid for", money.spent == hollow, money.spent)
local cash = money.cash
Plan.Remove("loose:primary:hollow")
T("and paid back", money.cash == cash + hollow, money.cash - cash)

-- Deployables and the other items cost money too.
local kit = Plan.AddPrice("first_aid_kit")
T("a first aid kit has a price", kit == Ammo.PRICES.item.first_aid_kit and kit > 0, kit)
T("a doctor bag costs more than a first aid kit", Plan.AddPrice("doctor_bag") > kit)
money.spent = 0
local kits = Plan.Count("first_aid_kit")
T("adding a deployable pays for it", Plan.Add("first_aid_kit") == true and money.spent == kit
  and Plan.Count("first_aid_kit") == kits + 1, money.spent)
cash = money.cash
T("taking it out pays it back", Plan.Remove("first_aid_kit") == true and money.cash == cash + kit)
money.cash = kit - 1
T("not enough money for a deployable: it is not added", Plan.Add("doctor_bag") == false)
money.cash = 1000000
T("an item mod's own price counts", (function()
  PDTI.items.first_aid_kit.price = 123
  local v = Plan.AddPrice("first_aid_kit")
  PDTI.items.first_aid_kit.price = nil
  return v == 123
end)())

-- Never more back than was paid: a plan from before the prices was free.
Plan.Add("first_aid_kit")
PDTI.SetPlanPaid(0)
cash = money.cash
Plan.Remove("first_aid_kit")
T("what was never paid for is not paid back", money.cash == cash, money.cash - cash)

-- The menu shows it.
PDTI.SetUIOpen(true)
local function find(name)
  for _, w in ipairs(ENV.menus[#ENV.menus].children) do
    for _, c in ipairs(w.children) do if c.params.name == name then return c end end
  end
end
local cost_line = find("bring_cost")
T("the menu shows what the loadout is worth and your money", cost_line
  and cost_line.params.text:find(Ammo.Money(Plan.Cost()), 1, true) ~= nil
  and cost_line.params.text:find("you have", 1, true) ~= nil, cost_line and cost_line.params.text)
T("and what the next magazine costs", find("bring_pick_info_primary")
  and find("bring_pick_info_primary").params.text:find(Ammo.Money(price), 1, true) ~= nil,
  find("bring_pick_info_primary") and find("bring_pick_info_primary").params.text)
local kit_line = find("bring_line_first_aid_kit")
T("and what a deployable costs", kit_line and kit_line.params.text:find(Ammo.Money(kit), 1, true) ~= nil,
  kit_line and kit_line.params.text)
PDTI.SetUIOpen(false)

------------------------------------------------------------- the restock

-- The heist: the plan came paid; what is used up is paid again.
Plan.Add("first_aid_kit")
local r = Plan.StartRestock()
local brought = r.rounds.standard or 0
T("the heist knows what the plan brought", brought > 0 and (r.items.first_aid_kit or 0) >= 1, brought)
-- A player with a gun (not one of the mod's: rounds count as standard).
local gun = { total = 100, clip = 30 }
function gun:get_ammo_total() return self.total end
function gun:get_ammo_remaining_in_clip() return self.clip end
local gun_unit = { base = function() return gun end }
local grenades = { amount = 3 }
local player = { inventory = function() return { available_selections = function() return { { unit = gun_unit } } end } end }
local old_unit, old_pm = ENV.game.unit, {}
ENV.game.unit = player
for _, k in ipairs({ "get_grenade_amount" }) do old_pm[k] = managers.player[k] end
managers.player.get_grenade_amount = function() return grenades.amount end
managers.network = { session = function() return { local_peer = function() return { id = function() return 1 end } end } end }
managers.blackmarket.equipped_grenade = function() return "frag" end
tweak_data.blackmarket = tweak_data.blackmarket or {}
tweak_data.blackmarket.projectiles = { frag = {}, smoke_screen_grenade = { ability = true, base_cooldown = 60 } }

money.cash, money.spent = 1000000, 0
Plan.RestockTick()
T("nothing is paid while nothing is used", money.spent == 0, money.spent)
gun.clip, gun.total = 27, 97
Plan.RestockTick()
Plan.PayRestock(true)
T("three rounds fired: three rounds paid", money.spent == 3 * Ammo.RoundPrice("standard"), money.spent)
gun.clip = 30
Plan.RestockTick()
Plan.PayRestock(true)
T("a reload is not a round used", money.spent == 3 * Ammo.RoundPrice("standard"), money.spent)
gun.total = 197
Plan.RestockTick()
gun.total = 190
Plan.RestockTick()
Plan.PayRestock(true)
T("a magazine taken out of the gun on the ground is not paid", money.spent == 3 * Ammo.RoundPrice("standard"))
-- Firing far more than was brought (ammo boxes): at most what the plan brought.
gun.clip, gun.total = 0, 0
for _ = 1, 50 do
  gun.clip, gun.total = 1000, 1000
  Plan.RestockTick()
  gun.clip, gun.total = 0, 0
  Plan.RestockTick()
end
Plan.PayRestock(true)
T("never more rounds than the plan brought", money.spent == brought * Ammo.RoundPrice("standard"),
  money.spent .. " for " .. brought)
-- A deployable placed.
money.spent = 0
local entry = PDTI.FindItems(function(_, it) return it.item_id == "first_aid_kit" end)[1]
PDTI.RemoveItem(entry.container, entry.item.instance_id, 1)
Plan.RestockTick()
Plan.PayRestock(true)
T("a first aid kit used: paid again", money.spent == kit, money.spent)
-- Throwables.
money.spent = 0
Plan.RestockTick()
grenades.amount = 2
Plan.RestockTick()
Plan.PayRestock(true)
T("a grenade thrown: paid again", money.spent == Ammo.PRICES.throwable, money.spent)
grenades.amount = 5
Plan.RestockTick()
grenades.amount = 0
Plan.RestockTick()
Plan.PayRestock(true)
T("no more grenades paid than the heist started with", money.spent == 3 * Ammo.PRICES.throwable, money.spent)
T("abilities (perk deck throwables) are free", Ammo.ThrowablePrice("smoke_screen_grenade") == 0
  and Ammo.ThrowablePrice("frag") > 0)
-- Paid at most once a second.
money.spent = 0
r = Plan.StartRestock()
gun.clip, gun.total = 30, 100
Plan.RestockTick()
r.last_pay = nil
gun.clip, gun.total = 29, 99
Plan.RestockTick()
local first_pay = money.spent
gun.clip, gun.total = 28, 98
Plan.RestockTick()
T("the money is taken at most once a second", first_pay > 0 and money.spent == first_pay, money.spent)
Plan.PayRestock(true)
T("and nothing is lost", money.spent == 2 * Ammo.RoundPrice("standard"), money.spent)
Plan.restock = nil
ENV.game.unit = old_unit
managers.player.get_grenade_amount = old_pm.get_grenade_amount

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
