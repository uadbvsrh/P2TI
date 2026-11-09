-- Runs every test file of this mod, each in its own process.
--   texlua tests/run_all.lua
-- The InsurgencySandstormStyleReload mod is merged into this mod, so the
-- tests run the ammunition system of this mod itself.
local script = arg and arg[0] or "tests/run_all.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"

local files = {
    "run_tests.lua",
    "ui_tests.lua",
    "hooks_tests.lua",
    "ammo_tests.lua",
    "install_tests.lua",
    "loot_tests.lua",
    "deployable_tests.lua",
    "feed_tests.lua",
    "speed_tests.lua",
    "gear_tests.lua",
    "reload_tests.lua",
    "drag_tests.lua",
    "akimbo_tests.lua",
    "plan_tests.lua",
    "menu_tests.lua",
    "typed_ammo_tests.lua",
    "gun_slot_tests.lua",
    "akimbo_buttons_tests.lua",
    "body_tests.lua",
    "recoil_tests.lua",
    "hook_chain_tests.lua",
    "bag_price_tests.lua",
    "ammo_conservation_tests.lua"
}

-- The tests run with the interpreter that runs this script (luajit, lua or
-- texlua); PDTI_LUA overrides it.
local interpreter = os.getenv("PDTI_LUA")
if not interpreter or interpreter == "" then
    local i = -1
    while arg and arg[i - 1] do i = i - 1 end
    interpreter = (arg and arg[i]) or "luajit"
end

local failed = 0
local total_pass, total_fail = 0, 0
for _, file in ipairs(files) do
    print("\n=== " .. file .. " ===")
    local pipe = io.popen(interpreter .. " '" .. ROOT .. "tests/" .. file .. "' 2>&1")
    if not pipe then
        print("could not run " .. file)
        failed = failed + 1
    else
        local output = pipe:read("*a") or ""
        local ok, _, code = pipe:close()
        print(output)
        -- Lua 5.1 returns the raw status, 5.2+ returns true/"exit"/code
        local status = code
        if status == nil then status = ok and 0 or 1 end
        -- A file only counts as passed when it printed its summary with no
        -- failure (a missing interpreter prints nothing).
        local passed_n, failed_n = output:match("(%d+) passed, (%d+) failed")
        passed_n, failed_n = tonumber(passed_n), tonumber(failed_n)
        if passed_n then
            total_pass = total_pass + passed_n
            total_fail = total_fail + failed_n
        end
        if (type(status) == "number" and status ~= 0) or not passed_n or failed_n > 0 then
            failed = failed + 1
        end
    end
end

print(string.format("\n%d check(s) passed, %d failed", total_pass, total_fail))
print(string.format("%d test file(s) failed", failed))
os.exit(failed == 0 and 0 or 1)
