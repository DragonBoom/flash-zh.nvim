local flash = require("flash")
local flypy = require("flash-zh.flypy")

-- convert flypy for fuzzy {{{1

local is_fuzzy_merged = false

if not is_fuzzy_merged then
    local function get_field_plain_value(table, field)
        local v = table[field]
        return v and string.sub(v, 2, #v - 1) or ""
    end

    local function merge_fields(table, field_1, field_2)
        if table[field_1] and table[field_2] then
            table[field_1] = '[' .. get_field_plain_value(table, field_1) .. get_field_plain_value(table, field_2) .. ']'
            table[field_2] = table[field_1]
        end
    end

    merge_fields(flypy.char1patterns, 'u', 's')
    merge_fields(flypy.char1patterns, 'v', 'z')
    merge_fields(flypy.char1patterns, 'i', 'c')


    local function merge_double_fields(table, is_preifx, part_1, part_2)
        for i = 97, 122 do -- a~z
            local char = string.char(i)

            local field_1 = is_preifx and (part_1 .. char) or (char .. part_1)
            local field_2 = is_preifx and (part_2 .. char) or (char .. part_2)

            if table[field_1] then
                table[field_1] = '[' .. get_field_plain_value(table, field_1) .. get_field_plain_value(table, field_2) .. ']'
                table[field_2] = table[field_1]
            elseif table[field_2] then
                table[field_1] = table[field_2]
            end
        end
    end

    merge_double_fields(flypy.char2patterns, true, 'u', 's')
    merge_double_fields(flypy.char2patterns, true, 'v', 'z')
    merge_double_fields(flypy.char2patterns, true, 'i', 'c')

    merge_double_fields(flypy.char2patterns, false, 'h', 'j')
    merge_double_fields(flypy.char2patterns, false, 'g', 'f')

    -- iang <-> ian
    merge_double_fields(flypy.char2patterns, false, 'l', 'm')
    -- uang <-> uan
    merge_double_fields(flypy.char2patterns, false, 'l', 'r')
    -- ing <-> in
    merge_double_fields(flypy.char2patterns, false, 'k', 'b')
end

is_fuzzy_merged = true
-- }}}1

local M = {}

function M.jump(opts)
    local mode = M.mix_mode
    if opts.chinese_only then
        mode = M.zh_mode
    end
    opts = vim.tbl_deep_extend("force", {
        labels = "asdfghjklqwertyuiopzxcvbnm",
        search = {
            mode = mode,
        },
        labeler = function(_, state)
            require("flash-zh.labeler").new(state):update()
        end,
    }, opts or {})
    flash.jump(opts)
end

function M.mix_mode(str)
    local all_possible_splits = M.parser(str)
    local regexs = { [[\(]] }
    for _, v in ipairs(all_possible_splits) do
        regexs[#regexs + 1] = M.regex(v)
        regexs[#regexs + 1] = [[\|]]
    end
    regexs[#regexs] = [[\)]]
    local ret = table.concat(regexs)
    return ret, ret
end

function M.zh_mode(str)
    local regexs = {}
    while string.len(str) > 1 do
        regexs[#regexs + 1] = flypy.char2patterns[string.sub(str, 1, 2)]
        str = string.sub(str, 3)
    end
    if string.len(str) == 1 then
        regexs[#regexs + 1] = flypy.char1patterns[str]
    end
    local ret = table.concat(regexs)
    return ret, ret
end

local nodes = {
    alpha = function(str)
        return "[" .. str .. string.upper(str) .. "]"
    end,
    pinyin = function(str)
        return flypy.char2patterns[str]
    end,
    comma = function(str)
        return flypy.comma[str]
    end,
    singlepin = function(str)
        return flypy.char1patterns[str]
    end,
    other = function(str)
        str = flypy.escape[str] or str
        return str
    end,
}

function M.regex(parser)
    local regexs = {}
    for _, v in ipairs(parser) do
        regexs[#regexs + 1] = nodes[v.type](v.str)
    end
    return table.concat(regexs)
end

function M.parser(str, prefix)
    prefix = prefix or {}
    local firstchar = string.sub(str, 1, 1)
    if firstchar == "" then
        return { prefix }
    elseif string.match(firstchar, "%a") then
        local secondchar = string.sub(str, 2, 2)
        if secondchar == "" then
            local prefix2 = M.copy(prefix)
            prefix[#prefix + 1] = { str = firstchar, type = "alpha" }
            prefix2[#prefix2 + 1] = { str = firstchar, type = "singlepin" }
            return { prefix, prefix2 }
        elseif string.match(secondchar, "%a") then
            if flypy.char2patterns[firstchar .. secondchar] then
                local prefix2 = M.copy(prefix)
                prefix2[#prefix2 + 1] = { str = firstchar, type = "alpha" }
                prefix[#prefix + 1] = { str = firstchar .. secondchar, type = "pinyin" }
                local str2 = string.sub(str, 2, -1)
                str = string.sub(str, 3, -1)
                return M.merge_table(M.parser(str, prefix), M.parser(str2, prefix2))
            else
                prefix[#prefix + 1] = { str = firstchar, type = "alpha" }
                str = string.sub(str, 2, -1)
                return (M.parser(str, prefix))
            end
        elseif string.match(secondchar, "[%.,?'\"%[%];:]") then
            prefix[#prefix + 1] = { str = firstchar, type = "alpha" }
            prefix[#prefix + 1] = { str = secondchar, type = "comma" }
            str = string.sub(str, 3, -1)
            return M.parser(str, prefix)
        else
            prefix[#prefix + 1] = { str = firstchar, type = "alpha" }
            prefix[#prefix + 1] = { str = secondchar, type = "other" }
            str = string.sub(str, 3, -1)
            return M.parser(str, prefix)
        end
    elseif string.match(firstchar, "[%.,?'\"%[%];:]") then
        prefix[#prefix + 1] = { str = firstchar, type = "comma" }
        str = string.sub(str, 2, -1)
        return M.parser(str, prefix)
    else
        prefix[#prefix + 1] = { str = firstchar, type = "other" }
        str = string.sub(str, 2, -1)
        return M.parser(str, prefix)
    end
end

function M.merge_table(tab1, tab2)
    for i = 1, #tab2 do
        table.insert(tab1, tab2[i])
    end
    return tab1
end

function M.copy(table)
    local copy = {}
    for k, v in pairs(table) do
        copy[k] = v
    end
    return copy
end

return M
