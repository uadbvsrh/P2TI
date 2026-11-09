-- 0.18.5: armour-piercing and hollow-point rounds never come out of
-- nowhere. Random play (shots, reloads, ammo boxes, holding R, the
-- magazine taken out of the weapon's slot and put back) on a rifle and on
-- akimbo SMGs: after every step the special rounds you own (loose, in
-- magazines, in the gun) may only go down. Ammo bags are left out: they
-- refill special magazines with their own bullets on purpose.
--   luajit tests/ammo_conservation_tests.lua
local script = arg and arg[0] or "tests/ammo_conservation_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_conservation") .. "/")
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.load_mod(ROOT, false)
_G.Idstring = function(s) return "ids:" .. tostring(s) end
NewRaycastWeaponBase._get_current_damage = function(self, m) return 10 * (m or 1) end
NewRaycastWeaponBase.armor_piercing_chance = function() return 0.25 end
_G.CopDamage = { roll_critical_hit = function(_, a) return false, a.damage end }
dofile(ROOT .. "lua/ammo_hooks.lua")
local Ammo = PDTI.Ammo
Ammo.InstallHooks()

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end

local function run(seed, akimbo)
  math.randomseed(seed)
  PDTI.Reset(); Ammo.Reset(); Ammo.OnHeistStart(); PDTI.SetSessionOnly(true)
  PDTI.SetEquipment("rig", "general_rig"); PDTI.SetEquipment("backpack", "large_backpack")
  local unit = ENV.make_unit()
  local wep = ENV.make_weapon(akimbo and "test_akimbo_smg" or "test_ar", { "wpn_no_part" }, akimbo and 40 or 30)
  function wep:selection_index() return 2 end
  unit:set_weapon(wep); Ammo.EnsureSupply(wep)
  local info = Ammo.Identify(wep); local key = info.key
  for _, m in ipairs(Ammo.AllMagazines(key)) do PDTI.RemoveItem(m.container, m.instance_id) end
  Ammo.AddMagazineKey(key, 20, info, nil, { size = "compact", bullet = "ap" })
  Ammo.AddMagazineKey(key, 10, info, nil, { size = "standard", bullet = "hollow" })
  Ammo.AddMagazineKey(key, 30, info, nil, { size = "standard", bullet = "standard" })
  Ammo.AddMagazineKey(key, 0, info, nil, { size = "extended", bullet = "ap" })
  if akimbo then
    Ammo.SetLoaded(wep, { size = "standard", bullet = "ap" }, { size = "standard", bullet = "hollow" })
    wep._pdti_pair = { 20, 20 }; wep.clip = 40
  else
    Ammo.SetLoaded(wep, { size = "standard", bullet = "ap" }); wep.clip = 30
  end
  Ammo.ApplyLoaded(wep); Ammo.SyncTotal(wep)

  local function count(load, n) for _, part in ipairs(load or {}) do if part[1] ~= "standard" then n = n + part[2] end end return n end
  local function special()
    local n = Ammo.LooseOfKey(key, "ap") + Ammo.LooseOfKey(key, "hollow")
    for _, m in ipairs(Ammo.AllMagazines(key)) do n = count(m.load, n) end
    if akimbo then
      for _, v in ipairs(Ammo.PairViews(wep)) do n = count(v.load, n) end
    elseif not wep._issr_no_mag and not wep._issr_mag_gone then
      local spec = Ammo.LoadedSpec(wep) or {}
      local rounds = math.max(0, wep:get_ammo_remaining_in_clip() - Ammo.ChamberOf(wep))
      n = count(Ammo.FitLoad(spec.load and Ammo.ParseLoad(Ammo.LoadString(spec.load)) or {}, rounds, spec.bullet), n)
    end
    return n + Ammo.ChamberOf(wep)
  end
  local function gun_items() return PDTI.GetContainerInfo("gun_primary").items end
  local ops = {
    function() for _ = 1, math.random(1, 30) do if wep.clip > 0 then wep.clip = wep.clip - 1; NewRaycastWeaponBase._get_current_damage(wep, 1) end end end,
    function() if NewRaycastWeaponBase.can_reload(wep) then NewRaycastWeaponBase.on_reload(wep) end end,
    function() wep._ammo_pickup = { 5, 25 }; RaycastWeaponBase.add_ammo(wep, 1) end,
    function() Ammo.StartJob(wep); for _ = 1, math.random(1, 40) do Ammo.Tick(1) end end,
    function()
      local it = gun_items()[1]; if not it then return end
      local x, y = PDTI.FindFreeSpace("backpack", it.item_id, false)
      if x then PDTI.RequestMove("gun_primary", it.instance_id, "backpack", x, y, false) end
    end,
    function()
      if #gun_items() > 0 then return end
      local ms = Ammo.Magazines(key); local m = ms[math.random(1, math.max(1, #ms))]
      if m then PDTI.RequestMove(m.container, m.instance_id, "gun_primary", 0, 0, false) end
    end,
  }
  local prev = special()
  for step = 1, 200 do
    ops[math.random(1, #ops)]()
    Ammo.SyncGunSlot(wep); Ammo.SyncTotal(wep)
    local now = special()
    if now > prev then return false, string.format("step %d: %d -> %d", step, prev, now) end
    prev = now
  end
  return true
end

for _, akimbo in ipairs({ false, true }) do
  local bad = {}
  for seed = 1, 20 do
    local ok, why = run(seed, akimbo)
    if not ok then bad[#bad + 1] = "seed " .. seed .. " " .. why end
  end
  T((akimbo and "akimbo SMGs" or "a rifle") .. ": 20 random heists, no special round out of nowhere",
    #bad == 0, table.concat(bad, "; "))
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
