-- AI Control bar widget. Talks to the authenticated loopback bridge (see INSTALL.md).
-- Layout follows the native AI Control popover: per-CLI cards, a result banner and a
-- Settings view behind the gear. Only input/lifecycle/timer callbacks start services;
-- rendering stays pure. Clicks update the local snapshot at once (optimistic) and the
-- bridge reply replaces it with the real state.
local ok, loaded = pcall(require, "../../default/lib/look")
local look: any = if ok and type(loaded) == "table" then loaded else nil

local ALIAS = "^[a-z][a-z0-9_-]*$"
local WIDTH = 340
local INNER = WIDTH - 24
local HOVER = if look then look.hover else "foreground/0.08"
local WARN = "#FF9F0A"
local DANGER = "#FF453A"
local GOOD = "#30D158"
local POLL = 30          -- seconds between cheap status polls (usage is cached by the bridge)
local USAGE_RECHECK = 3  -- seconds between re-polls while the bridge refreshes usage
local PROVIDERS = {
    claude = { title = "Claude CLI", detail = "Saved logins · switches Claude Code", badge = "✳",
        active = "selected", activeLabel = "Selected", name = "Claude" },
    codex = { title = "Codex CLI", detail = "Saved logins · switches OpenAI Codex", badge = "CX",
        active = "inUse", activeLabel = "In use", name = "Codex" },
}

------------------------------------------------------------------------------
-- Look helpers (managed look when available, plain ui otherwise)
------------------------------------------------------------------------------

local function scale(ctx)
    return if look then look.scale(ctx) else 1
end

local function text(props)
    return if look then look.text(props) else ui.text(props)
end

local function glyph(props)
    return if look then look.glyph(props) else ui.symbol(props)
end

local function radius(value)
    return if look then look.radius(value) else value
end

local function iconButton(name, action, props)
    props = props or {}
    if look then return look.button(name, action, props) end
    props.w = props.w or 24
    props.h = props.h or 24
    props.radius = 6
    props.hover = HOVER
    props.onClick = action
    props[1] = ui.symbol{ name = name, size = 12, color = props.color }
    props.color = nil
    return ui.stack(props)
end

local function card(props)
    if look then return look.group(props) end
    props.pad = props.pad or 12
    props.gap = props.gap or 8
    props.radius = 12
    props.fill = "surface"
    props.center = false
    return ui.column(props)
end

local function dbg(...)
    omniwm.log("aic", ...)
end

------------------------------------------------------------------------------
-- Bridge access
------------------------------------------------------------------------------

-- Bridge options copied from ctx.data while OmniWM is invoking the widget (render,
-- trigger, handlers). Async callbacks (HTTP completions, timers) never read ctx.data:
-- OmniWM 0.8.0 rejected that with "ctx.data is only readable by its own instance".
local config = { token = nil, port = 47820 }

local function remember(ctx)
    local ok, settings = pcall(function() return ctx.data.settings end)
    if ok and type(settings) == "table" then
        if type(settings.token) == "string" and settings.token ~= "" then config.token = settings.token end
        if type(settings.port) == "number" then config.port = settings.port end
    end
end

local function request(ctx, method, path, body, done)
    local token = config.token
    local port = config.port
    if type(token) ~= "string" or token == "" then
        done(nil, "No bridge token configured")
        return
    end
    local handle, reason = omniwm.http({
        url = "http://127.0.0.1:" .. tostring(port) .. path,
        method = method,
        headers = { Authorization = "Bearer " .. token, ["Content-Type"] = "application/json" },
        body = body, response = "json", maxBytes = 4194304, timeout = 120,
    }, function(result)
        if result.ok and type(result.json) == "table" then
            done(result.json, nil)
        else
            dbg("http", method, path, "status=" .. tostring(result.status), "error=" .. tostring(result.error))
            local message = if type(result.json) == "table" and type(result.json.message) == "string"
                then result.json.message
                elseif result.error == "network_not_approved" or result.error == "network_denied"
                then "Allow 127.0.0.1 in OmniWM Settings › Network & Permissions"
                else "AI Control bridge unavailable"
            done(nil, message)
        end
    end)
    if not handle then
        dbg("http refused", method, path, tostring(reason))
        done(nil, "AI Control bridge unavailable")
    end
end

local function validSnapshot(data)
    return type(data) == "table" and type(data.claude) == "table" and type(data.codex) == "table"
end

local poll
local load

-- GET status; while the bridge is refreshing usage, check again shortly.
load = function(ctx, path: string?)
    if ctx.state.loading then return end
    ctx.state.loading = true
    local started, problem = pcall(request, ctx, "GET", path or "/status", nil, function(data, message)
        ctx.state.loading = false
        if validSnapshot(data) then
            ctx.state.snapshot = data
            ctx.state.offline = nil
            if data.usageRefreshing and not ctx.state.recheck then
                ctx.state.recheck = omniwm.after(USAGE_RECHECK, function()
                    ctx.state.recheck = nil
                    load(ctx)
                end)
            end
        else
            ctx.state.offline = message or "AI Control bridge unavailable"
        end
    end)
    if not started then
        ctx.state.loading = false
        dbg("load failed", tostring(problem))
    end
end

-- Re-arms before loading so one failing poll can never stop polling.
poll = function(ctx)
    ctx.state.timer = omniwm.after(POLL, function() poll(ctx) end)
    load(ctx)
end

local function ensurePolling(ctx)
    if not ctx.state.timer then poll(ctx) end
end

function trigger(ctx, event)
    remember(ctx)
    if event.name == "reloaded" then
        if ctx.state.timer then ctx.state.timer:cancel() end
        ctx.state.timer = nil
        poll(ctx)
    elseif event.name == "refresh" then
        ensurePolling(ctx)
        load(ctx, "/status?usage=1")
    end
end

-- OmniWM hands HTTP JSON to widgets as readonly (frozen) tables: never mutate a snapshot,
-- change a deep copy instead.
local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in value do copy[key] = deepCopy(item) end
    return copy
end

local function findLogin(snapshot, tool: string, name: string)
    if not snapshot or type(snapshot[tool]) ~= "table" then return nil end
    for _, login in ipairs(snapshot[tool].logins or {}) do
        if login.name == name then return login end
    end
    return nil
end

-- POST an action: apply `optimistic(snapshot)` immediately, show `marker` as pending,
-- then adopt the bridge's snapshot (or reload and show the error).
local function act(path: string, payload, marker: string, success: string, optimistic)
    return function(next)
        if next.state.pending then
            dbg("click ignored (pending)", path, marker)
            return
        end
        local body = json.encode(payload)
        if not body then return end
        dbg("click", path, marker)
        next.state.pending = marker
        next.state.banner = nil
        if optimistic and next.state.snapshot then
            -- A failing preview must never block the real action or leave `pending` set.
            local preview = deepCopy(next.state.snapshot)
            local applied, problem = pcall(optimistic, preview)
            if applied then
                next.state.snapshot = preview
            else
                dbg("preview failed", path, tostring(problem))
            end
        end
        request(next, "POST", path, body, function(reply, message)
            next.state.pending = nil
            if reply and reply.ok then
                if validSnapshot(reply.snapshot) then next.state.snapshot = reply.snapshot end
                next.state.banner = { text = success, tone = "info" }
            else
                next.state.banner = { text = message or "Nothing changed.", tone = "warn" }
                load(next)
            end
        end)
    end
end

------------------------------------------------------------------------------
-- Usage formatting
------------------------------------------------------------------------------

local function windowsOf(login)
    if type(login) ~= "table" or type(login.usage) ~= "table" or type(login.usage.windows) ~= "table" then
        return {}
    end
    local list = {}
    for _, window in ipairs(login.usage.windows) do
        if type(window) == "table" and type(window.usedPercent) == "number" then
            list[#list + 1] = window
        end
    end
    return list
end

local function percentOf(value: number)
    return math.clamp(math.floor(value + 0.5), 0, 100)
end

local function used(login)
    local window = windowsOf(login)[1]
    return if window then percentOf(window.usedPercent) else nil
end

local function usageColor(percent: number)
    if percent >= 85 then return DANGER end
    if percent >= 60 then return WARN end
    return "accent"
end

local function windowLabel(window, index: number)
    return if type(window.label) == "string" and window.label ~= "" then window.label else "Usage " .. tostring(index)
end

local function windowText(ctx, window, index: number)
    local label = windowLabel(window, index) .. " " .. tostring(percentOf(window.usedPercent)) .. "%"
    if type(window.resetsAtEpoch) == "number" then
        local reset = ctx.format.date(window.resetsAtEpoch, "EEE h:mm a")
        if reset then label = label .. " · " .. reset end
    end
    return label
end

local function tokens(count: number)
    if count >= 1e9 then return string.format("%.1fB", count / 1e9) end
    if count >= 1e6 then return string.format("%.1fM", count / 1e6) end
    if count >= 1e3 then return string.format("%.1fK", count / 1e3) end
    return tostring(count)
end

------------------------------------------------------------------------------
-- Bar chip
------------------------------------------------------------------------------

-- Opening the popout is the moment to load fresh usage (the bridge limits it to once a
-- minute); while AI Control's "Refresh usage every" is off, nothing else fetches usage.
-- The chip sets `popout = true` so OmniWM opens the popout itself after this handler runs:
-- calling ui.popout(next) from inside a handler does not open it (observed on 0.8.0).
local function openPopout(next)
    remember(next)
    dbg("chip click (popout + usage)")
    ensurePolling(next)
    load(next, "/status?usage=1")
end

function render(ctx)
    remember(ctx)
    local s = scale(ctx)
    local snapshot = ctx.state.snapshot
    local name = snapshot and snapshot.claude.selected
    local login = if type(name) == "string" then findLogin(snapshot, "claude", name) else nil
    local props: any = { onClick = openPopout, popout = true, gap = 5 * s,
        help = "AI Control — Claude account and usage (percent used)" }
    if ctx.state.offline then
        props[1] = glyph{ name = "exclamationmark.triangle.fill", size = 13 * s, color = WARN }
    else
        props[1] = glyph{ name = "sparkle", size = 13 * s }
    end
    props[2] = text{ text = if type(name) == "string" then name else "aic", size = 13 * s }
    local percent = if login then used(login) else nil
    if percent then
        props[3] = text{ text = tostring(percent) .. "%", size = 13 * s, reserve = "100%",
            color = if percent >= 60 then usageColor(percent) else "secondaryForeground" }
    end
    if look then return look.bar(ctx, props) end
    props.pad = 4
    props.radius = 6
    props.hover = HOVER
    return ui.row(props)
end

------------------------------------------------------------------------------
-- Accounts view
------------------------------------------------------------------------------

local function orderOf(snapshot, tool: string)
    local auto = type(snapshot.settings) == "table" and type(snapshot.settings.autoSwitch) == "table"
        and snapshot.settings.autoSwitch or {}
    local order = (if tool == "codex" then auto.codexOrder else auto.claudeOrder)
    return if type(order) == "table" then order else {}
end

-- Saved auto-switch order first, then the rest by name (same rule as AI Control).
local function ordered(snapshot, tool: string, logins)
    local rank = {}
    for index, name in ipairs(orderOf(snapshot, tool)) do rank[name] = index end
    local list = table.clone(logins)
    table.sort(list, function(a, b)
        local ra, rb = rank[a.name] or math.huge, rank[b.name] or math.huge
        if ra ~= rb then return ra < rb end
        return tostring(a.name) < tostring(b.name)
    end)
    return list
end

local function moveOptimistic(tool: string, name: string, direction: string, names)
    return function(snapshot)
        local list = table.clone(names)
        local index = table.find(list, name)
        local other = if index then (if direction == "up" then index - 1 else index + 1) else nil
        if not index or not other or other < 1 or other > #list then return end
        list[index], list[other] = list[other], list[index]
        if type(snapshot.settings) == "table" and type(snapshot.settings.autoSwitch) == "table" then
            snapshot.settings.autoSwitch[if tool == "codex" then "codexOrder" else "claudeOrder"] = list
        end
    end
end

local function renameEditor(ctx, tool: string, name: string)
    local draft = ctx.state.draft or ""
    local valid = string.match(draft, ALIAS) ~= nil and #draft <= 32 and draft ~= name
        and findLogin(ctx.state.snapshot, tool, draft) == nil
    local function cancel(next)
        next.state.renaming = nil
        next.state.draft = nil
    end
    local function commit(next)
        local value = next.state.draft or ""
        if string.match(value, ALIAS) == nil or #value > 32 or value == name
            or findLogin(next.state.snapshot, tool, value) ~= nil then
            return
        end
        next.state.renaming = nil
        next.state.draft = nil
        act("/rename", { tool = tool, name = name, newName = value }, tool .. ":" .. value,
            "Renamed " .. PROVIDERS[tool].name .. " login " .. name .. " to " .. value .. ".",
            function(snapshot)
                local login = findLogin(snapshot, tool, name)
                if login then login.name = value end
                local key = PROVIDERS[tool].active
                if snapshot[tool][key] == name then snapshot[tool][key] = value end
            end)(next)
    end
    local hint = if draft == "" or valid then ""
        elseif findLogin(ctx.state.snapshot, tool, draft) ~= nil and draft ~= name then "That name is taken"
        else "Lowercase letters, digits, - and _ (max 32)"
    return ui.column{ w = INNER, gap = 6, center = false,
        text{ text = "New name for " .. name, size = 12, color = "secondaryForeground" },
        ui.input{ key = "rename:" .. tool .. ":" .. name, text = draft, placeholder = name, maxLength = 32,
            focus = true, size = 13,
            onChange = function(next, event) next.state.draft = event.text or "" end,
            onCommit = commit, onCancel = cancel },
        ui.row{ w = INNER, gap = 6,
            text{ text = hint, size = 11, color = WARN, grow = 1 },
            ui.row{ pad = 6, radius = 6, hover = HOVER, onClick = cancel, text{ text = "Cancel", size = 12 } },
            ui.row{ pad = 6, radius = 6, hover = if valid then HOVER else nil,
                onClick = if valid then commit else nil, opacity = if valid then 1 else 0.4,
                text{ text = "Save", size = 12, weight = "semibold", color = "accent" } } } }
end

local function statusLine(login, managed: boolean)
    if login.needsLogin then
        return ui.row{ gap = 5,
            glyph{ name = "exclamationmark.circle.fill", size = 12, color = WARN },
            text{ text = "Sign in again", size = 12, weight = "medium", color = WARN } }
    end
    if not managed then
        return ui.row{ gap = 5,
            glyph{ name = "info.circle", size = 12, color = "secondaryForeground" },
            text{ text = "Uppercase name — switch it in the AI Control app", size = 11,
                color = "secondaryForeground" } }
    end
    return ui.row{ gap = 5,
        glyph{ name = "checkmark.circle.fill", size = 12, color = GOOD },
        text{ text = "Saved", size = 12, weight = "medium", color = GOOD } }
end

local function usageGrid(ctx, login, width: number)
    local windows = windowsOf(login)
    if #windows == 0 then return nil end
    local column = (width - 8 * (#windows - 1)) / #windows
    local items: any = { w = width, gap = 8 }
    for index, window in ipairs(windows) do
        local percent = percentOf(window.usedPercent)
        items[#items + 1] = ui.column{ w = column, gap = 4, center = false,
            text{ text = windowText(ctx, window, index), size = 11, color = "secondaryForeground",
                maxWidth = column },
            ui.progress{ value = percent / 100, w = column, h = 4, radius = 2, fill = "foreground/0.1",
                color = usageColor(percent) } }
    end
    return ui.row(items)
end

local function loginRow(ctx, tool: string, login, names, index: number)
    local provider = PROVIDERS[tool]
    local snapshot = ctx.state.snapshot
    local name = tostring(login.name)
    local marker = tool .. ":" .. name
    local active = snapshot[tool][provider.active] == name
    local managed = string.match(name, ALIAS) ~= nil
    local pending = ctx.state.pending == marker
    local idle = ctx.state.pending == nil

    if ctx.state.renaming == marker then
        return ui.column{ key = "row:" .. marker, w = INNER, pad = 8, radius = radius(10), fill = "accent/0.08",
            center = false, renameEditor(ctx, tool, name) }
    end

    local title: any = { w = INNER - 16, gap = 6,
        text{ text = name, size = 14, weight = "semibold", maxWidth = INNER - 170 } }
    if active then
        title[#title + 1] = glyph{ name = "checkmark", size = 11, weight = "bold", color = "accent" }
        title[#title + 1] = text{ text = provider.activeLabel, size = 12, weight = "medium", color = "accent" }
    end
    if pending then
        title[#title + 1] = text{ text = "Working…", size = 11, color = "secondaryForeground" }
    end
    title[#title + 1] = ui.box{ grow = 1, h = 1 }
    if managed and idle then
        if index > 1 then
            title[#title + 1] = iconButton("chevron.up", act("/move", { tool = tool, name = name, direction = "up" },
                marker, "Moved " .. name .. " up.", moveOptimistic(tool, name, "up", names)),
                { w = 22, h = 22, help = "Earlier in the automatic switching order" })
        end
        if index < #names then
            title[#title + 1] = iconButton("chevron.down", act("/move", { tool = tool, name = name, direction = "down" },
                marker, "Moved " .. name .. " down.", moveOptimistic(tool, name, "down", names)),
                { w = 22, h = 22, help = "Later in the automatic switching order" })
        end
        title[#title + 1] = iconButton("pencil", function(next)
            next.state.renaming = marker
            next.state.draft = name
        end, { w = 22, h = 22, help = "Rename" })
    end

    local row: any = { key = "row:" .. marker, w = INNER, gap = 5, pad = 8, radius = radius(10), center = false,
        fill = if active then "accent/0.12" else nil, ui.row(title), statusLine(login, managed) }

    local usage = type(login.usage) == "table" and login.usage or nil
    if type(login.email) == "string" or (usage and type(usage.resetsAvailable) == "number") then
        local line: any = { w = INNER - 16, gap = 5 }
        if type(login.email) == "string" then
            line[#line + 1] = glyph{ name = "person.crop.circle", size = 11, color = "secondaryForeground" }
            line[#line + 1] = text{ text = login.email, size = 12, color = "secondaryForeground",
                maxWidth = INNER - 120 }
        end
        line[#line + 1] = ui.box{ grow = 1, h = 1 }
        if usage and type(usage.resetsAvailable) == "number" and usage.resetsAvailable > 0 then
            line[#line + 1] = glyph{ name = "arrow.counterclockwise", size = 11, color = "secondaryForeground" }
            line[#line + 1] = text{ text = tostring(usage.resetsAvailable)
                .. (if usage.resetsAvailable == 1 then " reset" else " resets"), size = 12,
                color = "secondaryForeground" }
        end
        row[#row + 1] = ui.row(line)
    end
    local grid = usageGrid(ctx, login, INNER - 16)
    if grid then row[#row + 1] = grid end
    if login.usageStale then
        row[#row + 1] = text{ text = "Showing the last usage that loaded", size = 11, color = "secondaryForeground" }
    elseif type(login.usageError) == "string" and login.usageError ~= "" then
        row[#row + 1] = text{ text = login.usageError, size = 12, color = "secondaryForeground",
            maxWidth = INNER - 16, lines = 2 }
    end

    if managed and not active and idle then
        row.hover = HOVER
        row.help = "Switch " .. provider.name .. " to " .. name
        row.onClick = act("/use", { tool = tool, name = name }, marker,
            "Switched " .. provider.name .. " to " .. name .. ".",
            function(s) s[tool][provider.active] = name end)
    end
    return ui.column(row)
end

local function providerCard(ctx, tool: string)
    local provider = PROVIDERS[tool]
    local snapshot = ctx.state.snapshot
    local data = snapshot and snapshot[tool]
    local logins = if data and type(data.logins) == "table" then ordered(snapshot, tool, data.logins) else {}
    local names = {}
    for _, login in ipairs(logins) do names[#names + 1] = login.name end
    local refreshing = snapshot and snapshot.usageRefreshing == true
    local header = ui.row{ w = WIDTH, gap = 10,
        ui.stack{ w = 28, h = 28, radius = radius(7), fill = if tool == "claude" then "#D97757" else "foreground/0.12",
            text{ text = provider.badge, size = if tool == "claude" then 15 else 11, weight = "bold",
                color = "#FFFFFFFF" } },
        ui.column{ gap = 1, center = false, grow = 1,
            text{ text = provider.title, size = 13, weight = "semibold" },
            text{ text = if data and data.installed == false then "CLI not installed" else provider.detail,
                size = 11, color = if data and data.installed == false then WARN else "secondaryForeground" } },
        if refreshing
            then glyph{ name = "ellipsis", w = 28, h = 28, size = 13, color = "secondaryForeground" }
            else iconButton("arrow.clockwise", function(next)
                ensurePolling(next)
                load(next, "/status?usage=1")
            end, { help = "Reload saved " .. provider.title .. " logins and usage" }) }
    local body: any = { w = WIDTH, gap = 2, pad = 4 }
    if #logins == 0 then
        body[#body + 1] = ui.row{ w = INNER, pad = 8,
            text{ text = "No saved logins — add one in the AI Control app", size = 12, color = "secondaryForeground" } }
    end
    for index, login in ipairs(logins) do
        body[#body + 1] = loginRow(ctx, tool, login, names, index)
    end
    return ui.column{ w = WIDTH, gap = 8, center = false, header, card(body) }
end

local function monitorsCard(ctx)
    local monitors = ctx.state.snapshot and ctx.state.snapshot.monitors
    if type(monitors) ~= "table" or #monitors == 0 then return nil end
    local body: any = { w = WIDTH, gap = 10,
        text{ text = "Monitors", size = 13, weight = "semibold" } }
    for _, monitor in ipairs(monitors) do
        if type(monitor) == "table" then
            body[#body + 1] = text{ text = tostring(monitor.name or monitor.id or "Monitor"), size = 12,
                weight = "medium" }
            if type(monitor.error) == "string" and monitor.error ~= "" then
                body[#body + 1] = text{ text = monitor.error, size = 11, color = WARN, maxWidth = INNER, lines = 2 }
            end
            local grid = usageGrid(ctx, monitor, INNER)
            if grid then body[#body + 1] = grid end
            for _, model in ipairs(if type(monitor.models) == "table" then monitor.models else {}) do
                if type(model) == "table" then
                    body[#body + 1] = ui.row{ w = INNER, gap = 6,
                        text{ text = tostring(model.model) .. " · " .. tokens(tonumber(model.totalTokens) or 0)
                            .. " tokens", size = 11, grow = 1, maxWidth = INNER - 50 },
                        if type(model.usedPercent) == "number"
                            then text{ text = tostring(percentOf(model.usedPercent)) .. "%", size = 11,
                                style = "mono", color = usageColor(percentOf(model.usedPercent)) }
                            else nil }
                end
            end
        end
    end
    return card(body)
end

------------------------------------------------------------------------------
-- Settings view
------------------------------------------------------------------------------

local function switchControl(on: boolean)
    return ui.stack{ w = 34, h = 20, radius = 10, fill = if on then "accent" else "foreground/0.15",
        ui.box{ w = 16, h = 16, radius = 8, fill = "#FFFFFFFF", dx = if on then 7 else -7 } }
end

local function settingOptimistic(apply)
    return function(snapshot)
        if type(snapshot.settings) == "table" then apply(snapshot.settings) end
    end
end

local function toggleRow(ctx, label: string, detail: string?, key: string, on: boolean, apply)
    local idle = ctx.state.pending == nil
    local value = if on then "off" else "on"
    return ui.row{ key = "setting:" .. key, w = INNER, gap = 8, pad = 4, radius = radius(6),
        hover = if idle then HOVER else nil,
        onClick = if idle then act("/settings", { key = key, value = value }, "setting:" .. key,
            label .. (if on then " off." else " on."), settingOptimistic(function(s) apply(s, not on) end)) else nil,
        ui.column{ gap = 1, center = false, grow = 1,
            text{ text = label, size = 13 },
            if detail then text{ text = detail, size = 11, color = "secondaryForeground", maxWidth = INNER - 50 } else nil },
        if ctx.state.pending == "setting:" .. key
            then glyph{ name = "ellipsis", size = 12, color = "secondaryForeground" }
            else switchControl(on) }
end

local function stepperRow(ctx, label: string, key: string, value: number, format, step: number,
    low: number, high: number, apply)
    local idle = ctx.state.pending == nil
    local function change(target: number)
        if not idle or target == value then return nil end
        return act("/settings", { key = key, value = target }, "setting:" .. key,
            label .. " " .. format(target) .. ".", settingOptimistic(function(s) apply(s, target) end))
    end
    local down = math.max(low, value - step)
    local up = math.min(high, value + step)
    return ui.row{ key = "setting:" .. key, w = INNER, gap = 6, pad = 4,
        text{ text = label, size = 13, grow = 1 },
        iconButton("minus", change(down), { w = 24, h = 24, opacity = if down == value then 0.35 else 1 }),
        text{ text = format(value), size = 13, style = "mono", reserve = "60 min" },
        iconButton("plus", change(up), { w = 24, h = 24, opacity = if up == value then 0.35 else 1 }) }
end

local function settingsView(ctx)
    local snapshot = ctx.state.snapshot
    local settings = snapshot and snapshot.settings
    if type(settings) ~= "table" then
        return card{ w = WIDTH, text{ text = "Settings unavailable", size = 12, color = "secondaryForeground" } }
    end
    local auto = type(settings.autoSwitch) == "table" and settings.autoSwitch or {}
    local refreshing = type(settings.refresh) == "table" and settings.refresh or {}
    local threshold = tonumber(auto.thresholdPercent) or 99
    local interval = tonumber(refreshing.intervalSeconds) or 300
    local function percent(v: number) return tostring(v) .. "%" end
    local function minutes(v: number) return tostring(math.floor(v / 60)) .. " min" end
    return ui.column{ w = WIDTH, gap = 10, center = false,
        card{ w = WIDTH, gap = 4,
            text{ text = "Usage and switching", size = 13, weight = "semibold" },
            toggleRow(ctx, "Refresh usage every", nil, "refresh", refreshing.enabled == true,
                function(s, v) s.refresh.enabled = v end),
            stepperRow(ctx, "Refresh interval", "refresh-interval", interval, minutes, 300, 300, 3600,
                function(s, v) s.refresh.intervalSeconds = v end),
            toggleRow(ctx, "Switch Claude automatically", nil, "auto-switch-claude", auto.claude == true,
                function(s, v) s.autoSwitch.claude = v end),
            toggleRow(ctx, "Switch Codex automatically", nil, "auto-switch-codex", auto.codex == true,
                function(s, v) s.autoSwitch.codex = v end),
            stepperRow(ctx, "Switch at", "auto-switch-threshold", threshold, percent, 1, 50, 100,
                function(s, v) s.autoSwitch.thresholdPercent = v end),
            toggleRow(ctx, "Refresh in the background", "Keeps checking with the menu closed.",
                "background-refresh", auto.background == true, function(s, v) s.autoSwitch.background = v end),
            text{ text = "Switching accounts to get around usage limits may break provider terms and suspend accounts.",
                size = 11, color = "secondaryForeground", maxWidth = INNER, lines = 3 } } }
end

------------------------------------------------------------------------------
-- Popout
------------------------------------------------------------------------------

local function banner(ctx)
    local message = ctx.state.offline and { text = ctx.state.offline, tone = "warn" } or ctx.state.banner
    if not message then return nil end
    local warn = message.tone == "warn"
    return ui.row{ key = "banner", w = WIDTH, gap = 8, pad = 10, radius = radius(10),
        fill = if warn then "foreground/0.08" else "accent/0.12",
        glyph{ name = if warn then "exclamationmark.triangle.fill" else "info.circle", size = 12,
            color = if warn then WARN else "accent" },
        text{ text = message.text, size = 12, maxWidth = WIDTH - 40, lines = 3, grow = 1 } }
end

function popout(ctx)
    local view = ctx.state.view or "accounts"
    local header = ui.row{ w = WIDTH, gap = 10,
        ui.stack{ w = 34, h = 34, radius = radius(9), fill = "foreground/0.08",
            glyph{ name = "terminal.fill", size = 15, color = "accent" } },
        ui.column{ gap = 1, center = false, grow = 1,
            text{ text = "AI Control", size = 15, weight = "semibold" },
            text{ text = "Choose the account each CLI uses", size = 11, color = "secondaryForeground" } },
        if view == "settings"
            then iconButton("chevron.left", function(next) next.state.view = "accounts" end, { help = "Back" })
            else iconButton("gearshape", function(next) next.state.view = "settings" end, { help = "Settings" }) }
    local content: any = { w = WIDTH, gap = 12, center = false, header }
    if view == "settings" then
        content[#content + 1] = ui.row{ w = WIDTH, gap = 4, hover = HOVER, pad = 2, radius = radius(6),
            onClick = function(next) next.state.view = "accounts" end,
            glyph{ name = "chevron.left", size = 12, color = "secondaryForeground" },
            text{ text = "Back", size = 13, color = "secondaryForeground" },
            text{ text = "Settings", size = 13, weight = "semibold" } }
    end
    local note = banner(ctx)
    if note then content[#content + 1] = note end
    if not ctx.state.snapshot then
        content[#content + 1] = card{ w = WIDTH,
            text{ text = if ctx.state.loading then "Loading…" else "No data yet", size = 12,
                color = "secondaryForeground" } }
    elseif view == "settings" then
        content[#content + 1] = settingsView(ctx)
    else
        content[#content + 1] = providerCard(ctx, "claude")
        content[#content + 1] = providerCard(ctx, "codex")
        local monitors = monitorsCard(ctx)
        if monitors then content[#content + 1] = monitors end
    end
    content[#content + 1] = ui.row{ w = WIDTH, center = true,
        text{ text = "Open sessions keep working after a switch", size = 11, color = "secondaryForeground" } }
    local body = ui.column(content)
    if look then return look.panel(ctx, { w = WIDTH + 28, body }) end
    return ui.column{ key = "aic-menu", pad = 14, radius = 16, fill = "background", center = false, body }
end
