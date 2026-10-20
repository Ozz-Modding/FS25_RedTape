-- Loads a src/ file under plain Lua 5.1. The mod uses one piece of FS25's
-- own dialect that 5.1 can't parse: `continue`. Each loop that uses it is
-- rewritten as
--
--   for ... do repeat <body> until true end
--
-- with every `continue` in it turned into `break`, which then only leaves
-- the inner repeat. Nothing is added on a new line, so error line numbers
-- still match the file. A loop that has both `continue` and a real `break`
-- can't be rewritten this way and fails the load: change the code or
-- extend this.

local luau = {}

local KEYWORDS = {
    ["function"] = true, ["if"] = true, ["do"] = true, ["for"] = true, ["while"] = true,
    ["repeat"] = true, ["until"] = true, ["end"] = true, ["continue"] = true, ["break"] = true,
}

-- The keywords above, with their positions, skipping strings and comments.
local function tokenize(source)
    local tokens = {}
    -- Last character of code before the current one (comments don't count)
    local previous = nil
    local i = 1
    local length = #source

    local function skipLongBracket(start)
        local equals = source:match("^%[(=*)%[", start)
        if equals == nil then
            return nil
        end
        local close = "]" .. equals .. "]"
        local finish = source:find(close, start, true)
        assert(finish ~= nil, "unterminated long bracket at " .. start)
        return finish + #close
    end

    while i <= length do
        local c = source:sub(i, i)
        if c == "-" and source:sub(i + 1, i + 1) == "-" then
            local afterLong = skipLongBracket(i + 2)
            if afterLong ~= nil then
                i = afterLong
            else
                local newline = source:find("\n", i, true)
                i = newline ~= nil and newline or length + 1
            end
        elseif c == "\"" or c == "'" then
            local j = i + 1
            while j <= length do
                local d = source:sub(j, j)
                if d == "\\" then
                    j = j + 2
                elseif d == c then
                    break
                else
                    j = j + 1
                end
            end
            i = j + 1
            previous = c
        elseif c == "[" and skipLongBracket(i) ~= nil then
            i = skipLongBracket(i)
            previous = "]"
        elseif c:match("[%a_]") then
            local word = source:match("^[%w_]+", i)
            -- `.continue` / `:end` style field names are not keywords
            if KEYWORDS[word] and previous ~= "." and previous ~= ":" then
                table.insert(tokens, { word = word, start = i, finish = i + #word - 1 })
            end
            i = i + #word
            previous = "a"
        elseif c:match("%d") then
            i = i + #source:match("^[%w_%.]+", i)
            previous = "0"
        else
            if not c:match("%s") then
                previous = c
            end
            i = i + 1
        end
    end
    return tokens
end

function luau.transform(source, chunkName)
    local edits = {}
    local stack = {}

    local function innermostLoop(token)
        for i = #stack, 1, -1 do
            local block = stack[i]
            if block.kind == "function" then
                break
            end
            if block.kind == "loop" or block.kind == "repeat" then
                return block
            end
        end
        error(string.format("%s: %s outside a loop at %d", chunkName, token.word, token.start))
    end

    for _, token in ipairs(tokenize(source)) do
        local word = token.word
        if word == "for" or word == "while" then
            table.insert(stack, { kind = "loophead" })
        elseif word == "do" then
            local top = stack[#stack]
            if top ~= nil and top.kind == "loophead" then
                top.kind = "loop"
                top.doToken = token
            else
                table.insert(stack, { kind = "block" })
            end
        elseif word == "function" or word == "if" then
            table.insert(stack, { kind = word })
        elseif word == "repeat" then
            table.insert(stack, { kind = "repeat" })
        elseif word == "until" then
            table.remove(stack)
        elseif word == "end" then
            local block = table.remove(stack)
            assert(block ~= nil, chunkName .. ": unbalanced end at " .. token.start)
            if block.kind == "loop" and block.continues ~= nil then
                assert(not block.hasBreak, string.format(
                    "%s: loop at %d uses both continue and break, tests/luau.lua can't rewrite it",
                    chunkName, block.doToken.start))
                table.insert(edits, { at = block.doToken.finish + 1, text = " repeat" })
                table.insert(edits, { at = token.start, text = "until true " })
                for _, continueToken in ipairs(block.continues) do
                    table.insert(edits, { at = continueToken.start, remove = #"continue", text = "break" })
                end
            end
        elseif word == "continue" then
            local loop = innermostLoop(token)
            assert(loop.kind == "loop", chunkName .. ": continue inside repeat-until is not supported")
            loop.continues = loop.continues or {}
            table.insert(loop.continues, token)
        elseif word == "break" then
            innermostLoop(token).hasBreak = true
        end
    end
    assert(#stack == 0, chunkName .. ": unclosed block")

    table.sort(edits, function(a, b) return a.at > b.at end)
    for _, edit in ipairs(edits) do
        source = source:sub(1, edit.at - 1) .. edit.text .. source:sub(edit.at + (edit.remove or 0))
    end
    return source
end

-- dofile for a src/ file (path relative to the repo root)
function luau.dofile(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local chunk = assert(loadstring(luau.transform(source, path), "@" .. path))
    return chunk()
end

return luau
