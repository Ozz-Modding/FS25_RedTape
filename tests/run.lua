-- Unit test runner, Lua 5.1 (FS25's own dialect). Run from the repo root,
-- normally through test.bat:
--
--   lua tests/run.lua                         every tests/test_*.lua
--   lua tests/run.lua tests/test_foo.lua      just that one
--
-- Each test file runs in its own lua process, so files can't leak globals
-- into each other, and a failure (any error) ends its file there with the
-- traceback - no pcall, same rule as the mod. A file is a list of
--
--   test("what it checks", function()
--       local world = stubs.install()
--       ...
--   end)
--
-- with `stubs` (tests/stubs.lua) and the assert helpers below already
-- global.

local isWindows = package.config:sub(1, 1) == "\\"

local function runOne(path)
    stubs = dofile("tests/stubs.lua")

    local count = 0
    function test(name, func)
        io.write("  " .. name .. " ... ")
        io.flush()
        func()
        count = count + 1
        print("ok")
    end

    local function fail(message, level)
        error(message, level + 1)
    end

    function assertEquals(actual, expected, message)
        if actual ~= expected then
            fail(string.format("%sexpected %s, got %s", message ~= nil and (message .. ": ") or "",
                tostring(expected), tostring(actual)), 2)
        end
    end

    function assertNear(actual, expected, tolerance, message)
        if actual == nil or math.abs(actual - expected) > tolerance then
            fail(string.format("%sexpected %s (+/- %s), got %s", message ~= nil and (message .. ": ") or "",
                tostring(expected), tostring(tolerance), tostring(actual)), 2)
        end
    end

    function assertTrue(value, message)
        if not value then
            fail(message or "expected true", 2)
        end
    end

    print(path)
    dofile(path)
    print(string.format("  %d passed", count))
end

local function listTestFiles()
    local command = isWindows and "dir /b tests\\test_*.lua 2>nul" or "ls tests 2>/dev/null"
    local files = {}
    local pipe = io.popen(command)
    for line in pipe:lines() do
        local name = line:match("(test_[%w_]+%.lua)$")
        if name ~= nil then
            table.insert(files, "tests/" .. name)
        end
    end
    pipe:close()
    table.sort(files)
    return files
end

local function runAll()
    local interpreter = arg[-1]
    local files = listTestFiles()
    local failed = {}

    for _, path in ipairs(files) do
        local command = string.format("\"%s\" tests/run.lua %s", interpreter, path)
        if isWindows then
            -- cmd /c strips the outer quotes, so the quoted exe path survives.
            command = "\"" .. command .. "\""
        end
        local status = os.execute(command)
        if status ~= 0 and status ~= true then
            table.insert(failed, path)
        end
    end

    print("")
    if #failed == 0 then
        print(string.format("All %d test files passed.", #files))
        os.exit(0)
    end
    print(string.format("%d of %d test files FAILED:", #failed, #files))
    for _, path in ipairs(failed) do
        print("  " .. path)
    end
    os.exit(1)
end

if arg[1] ~= nil then
    runOne(arg[1])
else
    runAll()
end
