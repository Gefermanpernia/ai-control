--!nocheck
-- OmniWM 0.8.0 host emulator for the aic widget, driven against the real bridge.
-- Fidelity points copied from the target: omniwm.http JSON arrives as readonly (frozen)
-- tables, completions run asynchronously and the tree re-renders after every callback,
-- ctx.state is one table shared by the bar chip and its popout, the managed look library
-- is the real one. Errors thrown by any widget callback fail the scenario.
local net = require("@lune/net")
local serde = require("@lune/serde")
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local process = require("@lune/process")
local task = require("@lune/task")

local env = process.env
local PORT = tonumber(env.AIC_E2E_PORT)
local TOKEN = env.AIC_E2E_TOKEN
local WIDGET = env.AIC_E2E_WIDGET
local VENDOR = env.AIC_E2E_VENDOR

------------------------------------------------------------------------------
-- Host emulation
------------------------------------------------------------------------------

local errors = {}
local queue = {}
local timers = {}
local requests = {}
local now = 0

local function deepFreeze(value)
    if type(value) == "table" and not table.isfrozen(value) then
        for _, item in value do deepFreeze(item) end
        table.freeze(value)
    end
    return value
end

-- Host invocations (render, popout, trigger, input handlers) may read ctx.data; async
-- completions and timers may not. Stricter than OmniWM 0.8.0, which reported
-- "ctx.data is only readable by its own instance" from a timer (L27): widgets must not
-- depend on reading ctx.data outside a host invocation.
local hostDepth = 0
local function invoke(label, fn, ...)
    hostDepth += 1
    local ok, err = pcall(fn, ...)
    hostDepth -= 1
    if not ok then
        errors[#errors + 1] = label .. ": " .. tostring(err)
    end
    return ok
end

local function element(kind)
    return function(props)
        props = props or {}
        props.__kind = kind
        return props
    end
end

local popoutOpen = false
local ui = {
    component = element("component"), row = element("row"), column = element("column"), stack = element("stack"),
    box = element("box"), text = element("text"), input = element("input"), symbol = element("symbol"),
    icon = element("icon"), image = element("image"), progress = element("progress"), shader = element("shader"),
    glass = element("glass"), shape = element("shape"), path = element("path"), slider = element("slider"),
    -- Observed on OmniWM 0.8.0 (L26): calling ui.popout(ctx) from inside a custom handler does
    -- nothing; the popout opens when onClick IS ui.popout or the clicked node has popout = true.
    popout = function() end,
}

local function decodeJson(text)
    local ok, value = pcall(serde.decode, "json", text)
    if ok then return value end
    return nil
end

local omniwm = {
    log = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        print("    [log] " .. table.concat(parts, " "))
    end,
    http = function(request, callback)
        requests[#requests + 1] = request.method .. " " .. request.url:gsub("^http://127.0.0.1:%d+", "")
        local response = net.request({ url = request.url, method = request.method or "GET",
            headers = request.headers, body = request.body })
        local result = { ok = response.ok, status = response.statusCode, headers = response.headers,
            text = response.body, json = if request.response == "json" then decodeJson(response.body) else nil }
        if not response.ok then result.error = "http_" .. tostring(response.statusCode) end
        queue[#queue + 1] = function() callback(deepFreeze(result)) end
        return { cancel = function() end }
    end,
    after = function(seconds, callback)
        local timer = { at = now + seconds, callback = callback, cancelled = false }
        timer.cancel = function(self) self.cancelled = true end
        timers[#timers + 1] = timer
        return timer
    end,
    run = function() end,
}

local json = {
    null = nil,
    encode = function(value) return serde.encode("json", value), nil end,
    decode = function(text) return decodeJson(text), nil end,
}

local function loadModule(path, environment)
    local source = fs.readFile(path)
    return luau.load(source, { debugName = path, environment = environment })()
end

local function widgetEnv()
    local environment = { ui = ui, omniwm = omniwm, json = json }
    environment.require = function(name)
        if name == "../../default/lib/look" then
            local skinEnv = { ui = ui, omniwm = omniwm, json = json }
            local skin = loadModule(VENDOR .. "/default/lib/skin.luau", skinEnv)
            return skin({ capsules = true })
        end
        error("unexpected require " .. tostring(name))
    end
    return environment
end

local source = fs.readFile(WIDGET) .. "\nreturn { render = render, popout = popout, trigger = trigger }"
local widget = luau.load(source, { debugName = "widgets/aic/init.luau", environment = widgetEnv() })()

local function invokeAsync(label, fn, ...)
    local saved = hostDepth
    hostDepth = 0
    local ok, err = pcall(fn, ...)
    hostDepth = saved
    if not ok then
        errors[#errors + 1] = label .. ": " .. tostring(err)
    end
    return ok
end

local hostData = deepFreeze({ settings = { token = TOKEN, port = PORT },
    bar = { style = { height = 32, vertical = false, transparent = false, backgrounds = false } } })
local ctx = {
    data = setmetatable({}, {
        __index = function(_, key)
            if hostDepth == 0 then error("ctx.data is only readable by its own instance", 2) end
            return hostData[key]
        end,
        __newindex = function() error("attempt to modify a readonly table", 2) end,
    }),
    state = {},
    format = {
        date = function(seconds, template) return "D" .. tostring(seconds) end,
        percent = function(fraction) return tostring(math.floor(fraction * 100)) .. "%" end,
        number = function(value) return tostring(value) end,
    },
    select = function() return nil end,
}

local bar, panel
local function rerender()
    invoke("render", function() bar = widget.render(ctx) end)
    invoke("popout", function() panel = widget.popout(ctx) end)
end

local function flush()
    local guard = 0
    while #queue > 0 and guard < 50 do
        guard += 1
        local job = table.remove(queue, 1)
        invokeAsync("http callback", job)
        rerender()
    end
end

-- Advance emulated time, firing due timers (each followed by its completions).
local function advance(seconds)
    now += seconds
    local due = {}
    for _, timer in timers do
        if not timer.cancelled and not timer.fired and timer.at <= now then due[#due + 1] = timer end
    end
    for _, timer in due do
        timer.fired = true
        invokeAsync("timer", timer.callback)
        flush()
    end
end

local function trigger(name)
    invoke("trigger " .. name, widget.trigger, ctx, { name = name, source = "host" })
    rerender()
    flush()
end

------------------------------------------------------------------------------
-- Tree queries and input
------------------------------------------------------------------------------

local function walk(node, visit)
    if type(node) ~= "table" then return end
    visit(node)
    for _, child in ipairs(node) do walk(child, visit) end
end

local function findKey(root, key)
    local found
    walk(root, function(node) if node.key == key and not found then found = node end end)
    return found
end

local function findHelp(root, help)
    local found
    walk(root, function(node) if node.help == help and not found then found = node end end)
    return found
end

local function texts(root)
    local list = {}
    walk(root, function(node) if node.__kind == "text" then list[#list + 1] = node.text end end)
    return table.concat(list, " | ")
end

local function click(node, label)
    if not node then
        errors[#errors + 1] = "missing target: " .. label
        return false
    end
    if type(node.onClick) ~= "function" then
        errors[#errors + 1] = "not clickable: " .. label
        return false
    end
    invoke("click " .. label, node.onClick, ctx, { button = "left", clicks = 1 })
    if node.onClick == ui.popout or node.popout == true then popoutOpen = not popoutOpen end
    rerender()
    return true
end

local function fakeState()
    return serde.decode("json", fs.readFile(env.AIC_FAKE_STATE))
end

------------------------------------------------------------------------------
-- Scenarios
------------------------------------------------------------------------------

local results = {}
local function scenario(name, spec, body)
    errors = {}
    local ok, err = pcall(body)
    if not ok then errors[#errors + 1] = "assertion: " .. tostring(err) end
    local passed = #errors == 0
    results[#results + 1] = { name = name, spec = spec, passed = passed }
    print((if passed then "PASS " else "FAIL ") .. spec .. " " .. name)
    for _, message in errors do print("    " .. message) end
end

local function expect(condition, message)
    if not condition then error(message, 2) end
end

scenario("chip and popout load from the bridge", "S1,S5", function()
    trigger("reloaded")
    expect(ctx.state.snapshot ~= nil, "no snapshot after reloaded")
    expect(texts(bar):find("gerardo") ~= nil, "chip does not show selected account: " .. texts(bar))
    expect(findKey(panel, "row:claude:geferman") ~= nil, "no geferman row in popout")
end)

local function usageCalls()
    local count = 0
    for _, line in string.split(fs.readFile(env.AIC_FAKE_LOG), "\n") do
        if line:find("--usage", 1, true) then count += 1 end
    end
    return count
end

scenario("refresh off: polls never fetch usage; opening the popout does", "S12", function()
    expect(fakeState().settings.refresh.enabled == false, "fixture must have refresh off")
    for _ = 1, 3 do
        advance(30)
        task.wait(0.2)
    end
    expect(usageCalls() == 0, "usage fetched " .. usageCalls() .. " times while refresh is off")
    popoutOpen = false
    click(bar, "chip")
    expect(popoutOpen, "chip click did not open the popout")
    flush()
    for _ = 1, 10 do
        task.wait(0.3)
        advance(3)
        if usageCalls() > 0 and ctx.state.snapshot and not ctx.state.snapshot.usageRefreshing then break end
    end
    expect(usageCalls() == 1, "opening the popout fetched usage " .. usageCalls() .. " times (want 1)")
    expect(texts(findKey(panel, "row:claude:gerardo")):find("37%%") ~= nil, "usage not shown after opening")
end)

scenario("switch Claude to geferman (instant, then real)", "S2,S8", function()
    click(findKey(panel, "row:claude:geferman"), "row:claude:geferman")
    expect(texts(findKey(panel, "row:claude:geferman")):find("Selected") ~= nil,
        "row not shown as Selected before the bridge replies (no instant feedback)")
    flush()
    expect(fakeState().claude.selected == "geferman", "aic selected is " .. tostring(fakeState().claude.selected))
    expect(texts(bar):find("geferman") ~= nil, "chip not updated: " .. texts(bar))
end)

scenario("switch Claude back to gerardo", "S2", function()
    click(findKey(panel, "row:claude:gerardo"), "row:claude:gerardo")
    flush()
    expect(fakeState().claude.selected == "gerardo", "aic selected is " .. tostring(fakeState().claude.selected))
end)

scenario("switch Codex to prime and back to gerardo", "S2", function()
    click(findKey(panel, "row:codex:prime"), "row:codex:prime")
    flush()
    expect(fakeState().codex.inUse == "prime", "codex inUse is " .. tostring(fakeState().codex.inUse))
    click(findKey(panel, "row:codex:gerardo"), "row:codex:gerardo")
    flush()
    expect(fakeState().codex.inUse == "gerardo", "codex inUse is " .. tostring(fakeState().codex.inUse))
end)

scenario("switch Codex to a lowercase saved login (spare)", "S2", function()
    click(findKey(panel, "row:codex:spare"), "row:codex:spare")
    flush()
    expect(fakeState().codex.inUse == "spare", "codex inUse is " .. tostring(fakeState().codex.inUse))
    expect(texts(findKey(panel, "row:codex:spare")):find("In use") ~= nil, "spare not shown In use")
end)

scenario("move prime up in the Claude order", "S3", function()
    click(findHelp(findKey(panel, "row:claude:prime"), "Earlier in the automatic switching order"), "prime up")
    flush()
    local order = fakeState().settings.autoSwitch.claudeOrder
    expect(table.find(order, "prime") ~= nil and table.find(order, "prime") < table.find(order, "gerardo"),
        "claudeOrder is " .. serde.encode("json", order))
end)

scenario("rename geferman to gef2 and back", "S3", function()
    for _, pair in { { "geferman", "gef2" }, { "gef2", "geferman" } } do
        local from, to = pair[1], pair[2]
        click(findHelp(findKey(panel, "row:claude:" .. from), "Rename"), "pencil " .. from)
        local input = findKey(panel, "rename:claude:" .. from)
        expect(input ~= nil, "rename input not shown for " .. from)
        invoke("input change", input.onChange, ctx, { text = to, phase = "changed" })
        rerender()
        input = findKey(panel, "rename:claude:" .. from)
        invoke("input commit", input.onCommit, ctx, { text = to })
        rerender()
        flush()
        local names = {}
        for _, login in fakeState().claude.logins do names[#names + 1] = login.name end
        expect(table.find(names, to) ~= nil, "aic logins are " .. table.concat(names, ","))
    end
end)

scenario("settings: toggle Codex auto-switch and lower Switch at by 1", "S4,S9", function()
    click(findHelp(panel, "Settings"), "gear")
    local before = fakeState().settings.autoSwitch
    click(findKey(panel, "setting:auto-switch-codex"), "toggle codex")
    flush()
    expect(fakeState().settings.autoSwitch.codex == not before.codex, "codex auto-switch not toggled")
    local row = findKey(panel, "setting:auto-switch-threshold")
    local buttons = {}
    walk(row, function(node) if node ~= row and type(node.onClick) == "function" then buttons[#buttons + 1] = node end end)
    expect(#buttons >= 1, "no stepper buttons")
    click(buttons[1], "threshold minus")
    flush()
    expect(fakeState().settings.autoSwitch.thresholdPercent == before.thresholdPercent - 1,
        "threshold is " .. tostring(fakeState().settings.autoSwitch.thresholdPercent))
    click(findKey(panel, "setting:auto-switch-codex"), "toggle codex back")
    flush()
    click(findHelp(panel, "Back"), "back")
end)

scenario("reload usage from the card refresh button", "S5", function()
    local count = #requests
    click(findHelp(panel, "Reload saved Claude CLI logins and usage"), "claude refresh")
    flush()
    local asked = false
    for i = count + 1, #requests do
        if requests[i]:find("usage=1", 1, true) then asked = true end
    end
    expect(asked, "refresh did not request ?usage=1")
    for _ = 1, 10 do
        task.wait(0.3)
        advance(3)
        if ctx.state.snapshot and not ctx.state.snapshot.usageRefreshing then break end
    end
    expect(texts(findKey(panel, "row:claude:gerardo")):find("37%%") ~= nil,
        "gerardo usage not shown: " .. texts(findKey(panel, "row:claude:gerardo")))
end)

local failed = 0
for _, result in results do
    if not result.passed then failed += 1 end
end
print(string.format("%d/%d scenarios passed", #results - failed, #results))
process.exit(if failed == 0 then 0 else 1)
