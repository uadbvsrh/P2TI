-- PDTI offline regression tests. Run from the mod folder:
--   texlua tests/run_tests.lua      (or any Lua 5.1-5.4 / LuaJIT interpreter)
-- Uses a mocked json library, SavePath and log. These tests exercise the Lua
-- inventory model only; they say nothing about PAYDAY 2 engine integration.
local script = arg and arg[0] or "tests/run_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_run") .. "/"
os.execute("rm -rf " .. TMP .. " && mkdir -p " .. TMP)
_G.SavePath = TMP
local logs = {}
_G.log = function(m) logs[#logs + 1] = m end

-- tiny JSON (enough for the state shape)
local function enc(v)
  local t = type(v)
  if t == "table" then
    if #v > 0 or next(v) == nil then
      local o = {} for i, x in ipairs(v) do o[#o+1] = enc(x) end
      return "[" .. table.concat(o, ",") .. "]"
    end
    local o = {}
    for k, x in pairs(v) do o[#o+1] = string.format("%q", tostring(k)) .. ":" .. enc(x) end
    return "{" .. table.concat(o, ",") .. "}"
  elseif t == "string" then return string.format("%q", v):gsub("\\\n", "\\n")
  else return tostring(v) end
end
local function dec(s)
  local i = 1
  local function ws() i = s:find("%S", i) or #s + 1 end
  local val
  local function str()
    local j = i + 1; local out = {}
    while true do
      local c = s:sub(j, j)
      if c == "" then error("unterminated") end
      if c == '"' then break end
      if c == "\\" then j = j + 1; c = s:sub(j, j); c = ({n="\n", t="\t"})[c] or c end
      out[#out+1] = c; j = j + 1
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
        r[#r+1] = val(); ws(); local d = s:sub(i, i); i = i + 1
        if d == "]" then return r elseif d ~= "," then error("bad arr") end
      end
    elseif c == '"' then return str()
    elseif s:sub(i, i+3) == "true" then i = i + 4 return true
    elseif s:sub(i, i+4) == "false" then i = i + 5 return false
    elseif s:sub(i, i+3) == "null" then i = i + 4 return nil
    else local n = s:match("^-?[%d%.eE+-]+", i); if not n then error("bad value at " .. i) end i = i + #n return tonumber(n) end
  end
  local r = val(); ws(); if i <= #s then error("trailing") end return r
end
_G.json = { encode = enc, decode = dec }
local real_encode = enc
local function break_save() json.encode = function() error("injected failure") end end
local function fix_save() json.encode = real_encode end

local function load_all()
  for _, n in ipairs({"items","inventory","ammo","item_use","ui_model","ui_interaction",
    "loot","deployables","carry","diagnostics","selftest"}) do
    dofile(ROOT .. "lua/" .. n .. ".lua")
  end
end
load_all()

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function count(c) return #PDTI.GetContainer(c).items end
local function layout(c)
  local t = {}
  for _, it in ipairs(PDTI.GetContainer(c).items) do
    t[#t + 1] = it.instance_id .. ":" .. it.x .. "," .. it.y .. "," .. tostring(it.rotated) .. "x" .. tostring(it.amount)
  end
  return table.concat(t, ";")
end
local function write(path, s) local f = io.open(path, "w"); f:write(s); f:close() end
local PRIMARY = TMP .. "pdti_inventory.json"

-- Built-in model tests
local p, n, results = PDTI.RunSelfTests()
T("built-in self tests (" .. p .. "/" .. n .. ")", p == n)

-- Baseline content
local _, bag = PDTI.AddItemAuto("backpack", "doctor_bag", 1, nil, true)
local _, band = PDTI.AddItemAuto("pockets", "bandage", 3, nil, true)
PDTI.AddItemAuto("backpack", "first_aid_kit", 1, nil, true)

-- Failed-save rollback
break_save()
local before, nid = count("backpack"), PDTI.GetState().next_id
local r = PDTI.AddItemAuto("backpack", "doctor_bag", 1, nil, true)
fix_save()
T("AddItem rolls back on failed save", r == false and count("backpack") == before and PDTI.GetState().next_id == nid)

break_save(); local rp = PDTI.RemoveItem("pockets", band.instance_id, 1); fix_save()
T("partial RemoveItem rolls back", rp == false and PDTI.FindItem("pockets", band.instance_id).amount == 3)
break_save(); local rf = PDTI.RemoveItem("backpack", bag.instance_id); fix_save()
T("full RemoveItem rolls back", rf == false and PDTI.FindItem("backpack", bag.instance_id) ~= nil)

local lay = layout("backpack")
local fx, fy = PDTI.FindFreeSpace("backpack", "doctor_bag", true)
break_save(); PDTI.MoveItem("backpack", bag.instance_id, "backpack", fx or 5, fy or 5, false); fix_save()
T("MoveItem rolls back", layout("backpack") == lay)

break_save(); local ar = PDTI.AutoArrange("backpack", true); fix_save()
T("AutoArrange rolls back on failed save", ar == false and layout("backpack") == lay)
T("AutoArrange succeeds when saving works", PDTI.AutoArrange("backpack", true) == true)
local valid, errs = PDTI.ValidateState()
T("state valid after arrange", valid == true, errs and table.concat(errs, ";"))

_G.SavePath = "/nonexistent_dir_pdti/"
T("unwritable save dir rolls back add", PDTI.AddItemAuto("pockets", "bandage", 1, nil, true) == false)
_G.SavePath = TMP

-- Item use: reserve, apply, refund
local effects = 0
PDTI.RegisterItemUse("bandage", function() effects = effects + 1; return true end)
break_save()
local u1 = PDTI.UseItem("pockets", band.instance_id, {})
fix_save()
T("UseItem: no effect when consumption cannot be saved", u1 == false and effects == 0 and PDTI.FindItem("pockets", band.instance_id).amount == 3, "effects=" .. effects)

local u2 = PDTI.UseItem("pockets", band.instance_id, {})
T("UseItem: success consumes exactly one unit", u2 == true and effects == 1 and PDTI.FindItem("pockets", band.instance_id).amount == 2)

PDTI.RegisterItemUse("bandage", function() return false, "not needed" end)
local u3, why3 = PDTI.UseItem("pockets", band.instance_id, {})
T("UseItem: handler refusal keeps the item", u3 == false and why3 == "not needed" and PDTI.FindItem("pockets", band.instance_id).amount == 2)

PDTI.RegisterItemUse("bandage", function() error("boom") end)
local u4 = PDTI.UseItem("pockets", band.instance_id, {})
T("UseItem: handler error keeps the item", u4 == false and PDTI.FindItem("pockets", band.instance_id).amount == 2)

-- last unit of a stack: consumed on success, reinserted on failure
local _, single = PDTI.AddItemAuto("pockets", "painkillers", 1, nil, true)
local pk_pos = PDTI.FindItem("pockets", single.instance_id)
PDTI.RegisterItemUse("painkillers", function() return false end)
PDTI.UseItem("pockets", single.instance_id, {})
local back = PDTI.FindItem("pockets", single.instance_id)
T("UseItem: failed use of last unit restores item in place", back ~= nil and back.x == pk_pos.x and back.y == pk_pos.y and back.amount == 1)
PDTI.RegisterItemUse("painkillers", function() return true end)
PDTI.UseItem("pockets", single.instance_id, {})
T("UseItem: successful use of last unit removes item", PDTI.FindItem("pockets", single.instance_id) == nil)
local v2, e2 = PDTI.ValidateState()
T("state valid after item-use scenarios", v2 == true, e2 and table.concat(e2, ";"))

-- Persistence recovery (reload inventory.lua from disk)
PDTI.AddItemAuto("backpack", "painkillers", 1, nil, true) -- ensures a .bak exists
local expected = count("backpack") + count("pockets") + count("rig")
local function reload() dofile(ROOT .. "lua/inventory.lua"); return count("backpack") + count("pockets") + count("rig") end
T("clean reload keeps all items", reload() == expected)
write(PRIMARY, '{"schema_version":4,"containers":{"pockets":{"items":[{"instance_id":')
local got = reload()
T("truncated primary recovers from backup", got >= 1 and got <= expected, got)
os.remove(PRIMARY)
T("missing primary recovers from backup", reload() >= 1)
write(PRIMARY, "")
T("empty primary recovers from backup", reload() >= 1)
write(PRIMARY, "garbage"); write(PRIMARY .. ".bak", "{{{")
T("both files corrupt starts empty without error", reload() == 0)

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
