--[[
  PresetBanks для grandMA2 — генератор наборов пресетов и эффектов.

  Смысловой аналог одноимённого плагина для grandMA3, но НЕ его порт: у MA2
  другая архитектура, и попытка перенести решение MA3 строку в строку дала бы
  неработающий код. Что именно различается — в таблице ниже и в README.

  ┌──────────────────────┬─────────────────────────┬──────────────────────────┐
  │                      │ grandMA3                │ grandMA2                 │
  ├──────────────────────┼─────────────────────────┼──────────────────────────┤
  │ универсальный прибор │ есть (Universal 1)      │ НЕТ                      │
  │ откуда берутся значения │ с универсального прибора │ с текущей выборки     │
  │ эффекты              │ фейзеры внутри пресета  │ отдельный пул Effect 1.x │
  │ описание эффекта     │ шаги и слои шагов       │ линии: форма, low/high,  │
  │                      │                         │ phase, width, rate       │
  │ «работает на всех»   │ Store /Universal        │ пресеты: Store /u        │
  │                      │                         │ эффекты: режим Template  │
  │ Lua API              │ Cmd, MessageBox         │ gma.cmd, gma.gui.*       │
  │ диалог с полями      │ MessageBox с inputs     │ НЕТ, только textinput    │
  └──────────────────────┴─────────────────────────┴──────────────────────────┘

  ─── Запуск ───

  Аргумент передаётся пользовательской переменной, как принято в MA2:

    SetVar $PB "color 101 full" ; Plugin "PresetBanks"
    SetVar $PB "dim 1 basic"    ; Plugin "PresetBanks"
    SetVar $PB "pos 10 basic 20"; Plugin "PresetBanks"
    SetVar $PB "colorfx 20 basic 60" ; Plugin "PresetBanks"
    SetVar $PB "list"           ; Plugin "PresetBanks"
    SetVar $PB "help"           ; Plugin "PresetBanks"

  Переменная не задана — плагин спросит строку через textinput.

  ─── Что требует выборки, а что нет ───

  Банк color пишет ПРЕСЕТЫ и требует выбранных приборов: универсального
  прибора в MA2 нет, значения берутся с реальной выборки, а «работает на
  всех» обеспечивает опция /u при сохранении.

  Банки dim, pos, colorfx пишут ЭФФЕКТЫ и выборки не требуют: эффект
  собирается командами Assign без привязки к приборам и остаётся шаблоном
  (Template) — в углу объекта пула буква T.

  ─── Откат ───

    Delete Preset <пул>.<первый> Thru <пул>.<последний>
    Delete Effect 1.<первый> Thru 1.<последний>

  Точная команда печатается в командную строку и показывается в финальном окне.
]]

-- ─── Общие настройки ────────────────────────────────────────────────────────

local PLUGIN = "PresetBanks"

-- Имя пользовательской переменной с аргументом.
local ARG_VAR = "PB"

-- Пул эффектов в MA2 всегда 1: обращение вида Effect 1.25, а не Effect 25.
-- MA Lighting заложили возможность нескольких пулов эффектов, но так её и не
-- использовали — номер остаётся единицей.
local EFFECT_POOL = 1

local DEFAULT_SPEED = 60     -- BPM в поле Speed линии эффекта
local DEFAULT_RATE  = 1

-- Номера форм из пула Form.
--
-- ⚠️ Это НЕ официальные значения: в документации MA таблицы форм нет, числа
-- взяты из рабочих макросов сообщества. Проверьте на своей консоли: откройте
-- пул Form и прочитайте номера, либо выберите форму в редакторе эффектов и
-- посмотрите обратную связь командной строки. Если номера у вас другие —
-- поправьте здесь, остальной код от этого не зависит.
local FORMS = {
  pwm    = 4,
  sin    = 8,
  cos    = 9,
  circle = 19,
}

-- ─── Конструкторы содержимого ───────────────────────────────────────────────

-- Линия эффекта. Поля соответствуют колонкам редактора эффектов MA2.
local function line(attribute, form, mode, low, high, phase, width)
  return { attribute = attribute, form = form, mode = mode,
           low = low, high = high, phase = phase or 0, width = width or 100 }
end

-- Статический цвет: три значения RGB 0..255, переведённые в проценты.
local function colour(name, r, g, b)
  local function pct(v) return v * 100.0 / 255.0 end
  return { name = name, values = {
    { attribute = "ColorRGB1", value = pct(r) },
    { attribute = "ColorRGB2", value = pct(g) },
    { attribute = "ColorRGB3", value = pct(b) },
  } }
end

-- ─── Банки ──────────────────────────────────────────────────────────────────
--
-- kind = "preset" — пишет в пул пресетов, требует выборки, хранит Store /u
-- kind = "effect" — пишет в пул эффектов, выборки не требует, остаётся Template

local BANKS = {

  {
    key = "color", title = "Цвета (статика)", kind = "preset",
    pool = 4, poolName = "Color",
    needsSelection = true,
    param = nil,
    defaultFirst = 101,
    defaultSet = "full",
    note = "Требует выбранных приборов с цветосмешением. Хранится Store /u — " ..
           "пресет применим ко всем приборам, у которых есть эти атрибуты.",
    warn = "Атрибуты ColorRGB1..3 есть только у приборов с цветосмешением. " ..
           "Приборы с колесом фильтров этим банком не покрываются — им нужен " ..
           "Color1 со слотом колеса.",
    sets = {
      { key = "basic", title = "Basic 12", members = {
        "White","Red","Orange","Amber","Yellow","Green",
        "Cyan","Sky","Blue","Violet","Magenta","Pink" } },
      { key = "full", title = "Full 24", members = {
        "White","Warm White","Cold White","Red","Deep Red","Orange","Amber",
        "Gold","Yellow","Lime","Green","Emerald","Turquoise","Cyan","Sky",
        "Blue","Deep Blue","Congo","Indigo","Violet","Magenta","Pink","Rose",
        "Lavender" } },
      { key = "tint", title = "Tints 12", members = {
        "Tint Straw","Tint Peach","Tint Rose","Tint Pink","Tint Lilac",
        "Tint Lavender","Tint Sky","Tint Aqua","Tint Mint","Tint Spring",
        "Tint Cream","Tint Ice" } },
    },
    items = {
      colour("White",        255, 255, 255),
      colour("Warm White",   255, 190, 130),
      colour("Cold White",   200, 220, 255),
      colour("Red",          255,   0,   0),
      colour("Deep Red",     190,   0,  20),
      colour("Orange",       255,  85,   0),
      colour("Amber",        255, 140,   0),
      colour("Gold",         255, 200,  40),
      colour("Yellow",       255, 255,   0),
      colour("Lime",         170, 255,   0),
      colour("Green",          0, 255,   0),
      colour("Emerald",        0, 255, 110),
      colour("Turquoise",      0, 255, 190),
      colour("Cyan",           0, 255, 255),
      colour("Sky",            0, 170, 255),
      colour("Blue",           0,  60, 255),
      colour("Deep Blue",      0,   0, 255),
      colour("Congo",         40,   0, 120),
      colour("Indigo",        75,   0, 255),
      colour("Violet",       140,   0, 255),
      colour("Magenta",      255,   0, 255),
      colour("Pink",         255,  80, 180),
      colour("Rose",         255, 140, 170),
      colour("Lavender",     200, 160, 255),
      colour("Tint Straw",   255, 235, 190),
      colour("Tint Peach",   255, 215, 185),
      colour("Tint Rose",    255, 205, 210),
      colour("Tint Pink",    255, 195, 225),
      colour("Tint Lilac",   225, 200, 255),
      colour("Tint Lavender",205, 210, 255),
      colour("Tint Sky",     195, 225, 255),
      colour("Tint Aqua",    195, 245, 245),
      colour("Tint Mint",    200, 245, 215),
      colour("Tint Spring",  220, 250, 195),
      colour("Tint Cream",   255, 245, 220),
      colour("Tint Ice",     230, 240, 255),
    },
  },

  {
    key = "dim", title = "Диммерные эффекты", kind = "effect",
    needsSelection = false,
    param = { name = "скорость", field = "speed", min = 1, max = 3000, default = DEFAULT_SPEED },
    defaultFirst = 1,
    defaultSet = "basic",
    note = "Одна линия на эффект, атрибут Dim, абсолютные значения.",
    sets = {
      { key = "basic", title = "Basic 5", members = {
        "Dim Sine","Dim Pulse","Dim Bump","Dim Ramp","Dim Strobe" } },
      { key = "full", title = "Full 5", members = {
        "Dim Sine","Dim Pulse","Dim Bump","Dim Ramp","Dim Strobe" } },
    },
    items = {
      { name = "Dim Sine",   note = "плавная синусоида",
        lines = { line("Dim", FORMS.sin, "abs", 0, 100) } },
      { name = "Dim Pulse",  note = "широкий импульс: PWM на половину доли",
        lines = { line("Dim", FORMS.pwm, "abs", 0, 100, 0, 50) } },
      { name = "Dim Bump",   note = "короткая вспышка: PWM на четверть доли",
        lines = { line("Dim", FORMS.pwm, "abs", 0, 100, 0, 25) } },
      { name = "Dim Ramp",   note = "пила: косинус даёт спад вместо подъёма",
        lines = { line("Dim", FORMS.cos, "abs", 0, 100) } },
      { name = "Dim Strobe", note = "частый жёсткий строб", speedMul = 10,
        lines = { line("Dim", FORMS.pwm, "abs", 0, 100, 0, 10) } },
    },
  },

  {
    key = "pos", title = "Позиционные эффекты", kind = "effect",
    needsSelection = false,
    param = { name = "размах, °", field = "size", min = 1, max = 180, default = 20 },
    defaultFirst = 10,
    defaultSet = "basic",
    note = "Относительные значения: смещение от текущей позиции прибора. " ..
           "Абсолютная позиция переносимой между приборами быть не может.",
    sets = {
      { key = "basic", title = "Basic 4", members = {
        "Pos Circle","Pos Pan Sweep","Pos Tilt Sweep","Pos Figure 8" } },
      { key = "shapes", title = "Shapes 3", members = {
        "Pos Diagonal","Pos Square","Pos Nod" } },
      { key = "full", title = "Full 7", members = {
        "Pos Circle","Pos Pan Sweep","Pos Tilt Sweep","Pos Figure 8",
        "Pos Diagonal","Pos Square","Pos Nod" } },
    },
    items = {
      -- Круг в MA2 делается синусом по Pan и косинусом по Tilt: косинус и есть
      -- сдвиг на 90°, отдельная фаза для этого не нужна.
      { name = "Pos Circle", note = "круг: Pan синус, Tilt косинус",
        lines = { line("Pan",  FORMS.sin, "rel", -1, 1),
                  line("Tilt", FORMS.cos, "rel", -1, 1) } },
      { name = "Pos Pan Sweep", note = "горизонтальный размах",
        lines = { line("Pan", FORMS.sin, "rel", -1, 1) } },
      { name = "Pos Tilt Sweep", note = "вертикальный размах",
        lines = { line("Tilt", FORMS.sin, "rel", -1, 1) } },
      { name = "Pos Figure 8", note = "восьмёрка: Tilt вдвое быстрее Pan",
        lines = { line("Pan",  FORMS.sin, "rel", -1, 1),
                  line("Tilt", FORMS.cos, "rel", -1, 1, 0, 100, 2) },
        lineRate = { 1, 2 } },
      { name = "Pos Diagonal", note = "линия: обе оси синусом в одной фазе",
        lines = { line("Pan",  FORMS.sin, "rel", -1, 1),
                  line("Tilt", FORMS.sin, "rel", -1, 1) } },
      { name = "Pos Square", note = "квадрат: PWM по обеим осям со сдвигом 90°",
        lines = { line("Pan",  FORMS.pwm, "rel", -1, 1,  0, 50),
                  line("Tilt", FORMS.pwm, "rel", -1, 1, 90, 50) } },
      { name = "Pos Nod", note = "мелкий кивок: 40 % размаха",
        lines = { line("Tilt", FORMS.sin, "rel", -0.4, 0.4) },
        lineRate = { 2 } },
    },
  },

  {
    key = "colorfx", title = "Цветовые эффекты", kind = "effect",
    needsSelection = false,
    param = { name = "скорость", field = "speed", min = 1, max = 3000, default = DEFAULT_SPEED },
    defaultFirst = 20,
    defaultSet = "basic",
    note = "Три линии по каналам ColorRGB1..3. Форму задаёт разница фаз: " ..
           "0/120/240 даёт вращение по кругу оттенков.",
    sets = {
      { key = "basic", title = "Basic 4", members = {
        "Col Rainbow","Col Warm Drift","Col Cold Drift","Col Red-Blue" } },
      { key = "full", title = "Full 5", members = {
        "Col Rainbow","Col Warm Drift","Col Cold Drift","Col Red-Blue","Col Police" } },
    },
    items = {
      { name = "Col Rainbow", note = "вращение по кругу оттенков, сдвиг 120°",
        lines = { line("ColorRGB1", FORMS.sin, "abs", 0, 100,   0),
                  line("ColorRGB2", FORMS.sin, "abs", 0, 100, 120),
                  line("ColorRGB3", FORMS.sin, "abs", 0, 100, 240) } },
      { name = "Col Warm Drift", note = "янтарь ↔ солома, красный держится",
        lines = { line("ColorRGB2", FORMS.sin, "abs", 50, 85, 0),
                  line("ColorRGB3", FORMS.sin, "abs",  0, 20, 0) } },
      { name = "Col Cold Drift", note = "лёд ↔ небо, синий держится",
        lines = { line("ColorRGB1", FORMS.sin, "abs", 55, 85, 0),
                  line("ColorRGB2", FORMS.sin, "abs", 80, 98, 0) } },
      { name = "Col Red-Blue", note = "жёсткий чейз красный ↔ синий",
        lines = { line("ColorRGB1", FORMS.pwm, "abs", 0, 100,   0, 50),
                  line("ColorRGB3", FORMS.pwm, "abs", 0, 100, 180, 50) } },
      { name = "Col Police", note = "то же на двойной скорости, вспышки короче",
        lines = { line("ColorRGB1", FORMS.pwm, "abs", 0, 100,   0, 25),
                  line("ColorRGB3", FORMS.pwm, "abs", 0, 100, 180, 25) },
        speedMul = 2 },
    },
  },
}

-- ─── Служебное ──────────────────────────────────────────────────────────────

local function say(fmt, ...)
  gma.echo(PLUGIN .. ": " .. string.format(fmt, ...))
  gma.feedback(PLUGIN .. ": " .. string.format(fmt, ...))
end

local function cmd(fmt, ...)
  gma.cmd(string.format(fmt, ...))
end

-- gma.gui.confirm появился в 3.2 и на 3.1.2.5 подвешивал консоль, поэтому
-- вызывается через pcall: на старой версии вместо зависания получим отказ.
local function confirm(title, message)
  local ok, res = pcall(function() return gma.gui.confirm(title, message) end)
  if not ok then
    gma.gui.msgbox(PLUGIN, "gma.gui.confirm недоступен на этой версии ПО.\n" ..
                           "Нужна grandMA2 3.2 или новее.")
    return false
  end
  return res and true or false
end

local function msg(title, message)
  gma.gui.msgbox(title, message)
end

-- Четыре знака после запятой без хвоста нулей: 100 остаётся «100»,
-- 74.5098 не превращается в «74.51».
local function num(v)
  local s = string.format("%.4f", v)
  s = s:gsub("0+$", ""):gsub("%.$", "")
  return s
end

local function bankByKey(key)
  if not key then return nil end
  key = string.lower(key)
  for _, b in ipairs(BANKS) do
    if b.key == key then return b end
  end
  return nil
end

local function setByKey(bank, key)
  if not key then return nil end
  key = string.lower(key)
  for _, s in ipairs(bank.sets) do
    if s.key == key then return s end
  end
  return nil
end

local function itemByName(bank, name)
  for _, it in ipairs(bank.items) do
    if it.name == name then return it end
  end
  return nil
end

local function bankKeyList()
  local out = {}
  for _, b in ipairs(BANKS) do out[#out + 1] = b.key end
  return table.concat(out, ", ")
end

-- Адрес объекта банка: пресет или эффект.
local function address(bank, idx)
  if bank.kind == "effect" then
    return string.format("Effect %d.%d", EFFECT_POOL, idx)
  end
  return string.format("Preset %d.%d", bank.pool, idx)
end

-- Существует ли объект. Вторая форма gma.show.getobj.handle принимает handle
-- и возвращает булево — этим и проверяется.
local function exists(bank, idx)
  local ok, res = pcall(function()
    local h = gma.show.getobj.handle(address(bank, idx))
    if not h then return false end
    return gma.show.getobj.handle(h) and true or false
  end)
  if not ok then return false end
  return res
end

local function occupiedRange(bank, first, count)
  local busy = {}
  for i = 0, count - 1 do
    if exists(bank, first + i) then busy[#busy + 1] = first + i end
  end
  return busy
end

local function describeBusy(busy, limit)
  limit = limit or 12
  local shown = {}
  for i = 1, math.min(#busy, limit) do shown[#shown + 1] = tostring(busy[i]) end
  local s = table.concat(shown, ", ")
  if #busy > limit then s = s .. ", … (+" .. (#busy - limit) .. ")" end
  return s
end

-- ─── Запись пресетов ────────────────────────────────────────────────────────

-- Универсального прибора в MA2 нет: значения задаются выбранным приборам, а
-- переносимость обеспечивает опция /u при сохранении. Поэтому выборку сбрасывать
-- нельзя — ClearAll снял бы и её. Очищаются только значения командой Clear,
-- которая оставляет выборку.
local function storePreset(bank, idx, item, name)
  gma.cmd("Clear")
  for _, v in ipairs(item.values) do
    cmd('Attribute "%s" At %s', v.attribute, num(v.value))
  end
  cmd("Store %s /u /o /nc", address(bank, idx))
  cmd('Label %s "%s"', address(bank, idx), (name:gsub('"', "'")))
end

-- ─── Запись эффектов ────────────────────────────────────────────────────────

-- Эффект собирается командами Assign и не привязывается к приборам, поэтому
-- остаётся шаблоном: в углу объекта пула буква T (Template) — «годен для всех
-- приборов, у которых есть эти атрибуты». Это и есть аналог универсального
-- пресета MA3 для эффектов.
local function storeEffect(bank, idx, item, name, size, speed)
  local addr = address(bank, idx)
  local n = #item.lines

  cmd("Store %s /o /nc", addr)
  cmd('Label %s "%s"', addr, (name:gsub('"', "'")))

  -- Линии создаются одной командой с Thru, если их больше одной.
  if n > 1 then
    cmd("Store Effect %d.%d.1 Thru %d.%d.%d /o", EFFECT_POOL, idx, EFFECT_POOL, idx, n)
  else
    cmd("Store Effect %d.%d.1 /o", EFFECT_POOL, idx)
  end

  for i, ln in ipairs(item.lines) do
    local la = string.format("Effect %d.%d.%d", EFFECT_POOL, idx, i)
    local rate = (item.lineRate and item.lineRate[i]) or DEFAULT_RATE
    local sp   = speed * (item.speedMul or 1)

    cmd('Assign Attribute "%s" %s', ln.attribute, la)
    cmd('Assign %s /mode="%s"', la, ln.mode)
    cmd("Assign Form %d %s", ln.form, la)
    cmd("Assign %s /rate=%s", la, num(rate))
    cmd("Assign %s /speed=%s", la, num(sp))
    cmd("Assign %s /phase=%s", la, num(ln.phase))
    cmd("Assign %s /width=%s", la, num(ln.width))

    -- Относительные значения — множители размаха: -1 при размахе 20 даёт -20°.
    local low  = (ln.mode == "rel") and (ln.low  * size) or ln.low
    local high = (ln.mode == "rel") and (ln.high * size) or ln.high
    cmd("Assign %s /lowvalue=%s /highvalue=%s", la, num(low), num(high))
  end
end

-- ─── Работа ─────────────────────────────────────────────────────────────────

local function createSet(task)
  local bank, first, set = task.bank, task.first, task.set
  local size  = task.size  or 1
  local speed = task.speed or DEFAULT_SPEED
  local prefix = task.prefix or ""
  local members = set.members
  local last = first + #members - 1

  -- Состав набора проверяется до первой команды: опечатка в members — ошибка
  -- правки файла, и ловить её на середине диапазона поздно.
  local plan = {}
  for i, name in ipairs(members) do
    local item = itemByName(bank, name)
    if not item then
      msg(PLUGIN .. " — ошибка набора",
          string.format("В наборе «%s» банка «%s» указан элемент «%s», " ..
                        "которого нет в items.\n\nНичего не записано.",
                        set.title, bank.key, tostring(name)))
      return
    end
    plan[i] = item
  end

  -- Банк пресетов требует выбранных приборов: брать значения не с чего.
  -- Проверить выборку из Lua нечем, поэтому спрашиваем прямо.
  if bank.needsSelection then
    if not confirm(PLUGIN .. " — нужна выборка",
        "Банк «" .. bank.title .. "» берёт значения с ВЫБРАННЫХ приборов: " ..
        "универсального прибора в MA2 нет.\n\n" ..
        "Приборы с цветосмешением уже выбраны?\n\n" ..
        "Значения в программере будут очищены (Clear); выборка сохранится.") then
      say("отменено: нет подтверждения выборки")
      return
    end
  end

  if bank.warn then
    if not confirm(PLUGIN .. " — предупреждение банка", bank.warn .. "\n\nПродолжить?") then
      say("отменено на предупреждении банка")
      return
    end
  end

  -- Подтверждение перезаписи — до первой команды записи.
  local busy = occupiedRange(bank, first, #members)
  if #busy > 0 then
    if not confirm(PLUGIN .. " — перезапись",
        string.format("Банк «%s».\nДиапазон %s Thru %d уже занят (%d шт.):\n%s\n\n" ..
                      "Эти объекты будут перезаписаны без возможности вернуть " ..
                      "прежнее содержимое.\n\nПродолжить?",
                      bank.title, address(bank, first), last, #busy, describeBusy(busy))) then
      say("отменено пользователем на шаге подтверждения перезаписи")
      return
    end
  end

  local paramNote = ""
  if bank.param then
    paramNote = string.format(", %s %s", bank.param.name,
                              num(bank.param.field == "size" and size or speed))
  end
  say("банк «%s», набор «%s», %d шт.%s → %s Thru %d",
      bank.key, set.title, #members, paramNote, address(bank, first), last)

  local bar = nil
  local okBar = pcall(function()
    bar = gma.gui.progress.start(PLUGIN)
    gma.gui.progress.setrange(bar, 0, #members)
  end)
  if not okBar then bar = nil end

  local written = 0
  for i, item in ipairs(plan) do
    local idx = first + i - 1
    local name = (prefix ~= "" and (prefix .. " ") or "") .. item.name

    if bank.kind == "effect" then
      storeEffect(bank, idx, item, name, size, speed)
    else
      storePreset(bank, idx, item, name)
    end

    -- Контрольный объект: первый записанный читается обратно. Если его нет,
    -- дальше идти незачем — самый дорогой сценарий здесь тот, где команды
    -- проходят без ошибок, а пул остаётся пустым.
    if i == 1 and not exists(bank, idx) then
      if bar then pcall(function() gma.gui.progress.stop(bar) end) end
      say("остановлено: контрольный объект %s не создан", address(bank, idx))
      msg(PLUGIN .. " — остановлено", string.format(
        "Контрольный объект %s после записи не найден.\n\n%s\n\n" ..
        "Остальные %d объектов не тронуты.",
        address(bank, idx),
        bank.kind == "preset"
          and "Обычная причина — приборы не выбраны либо у них нет атрибутов ColorRGB1..3."
          or  "Проверьте номера форм в начале файла: они не документированы MA " ..
              "и в вашем шоу могут отличаться.",
        #members - 1))
      return
    end

    written = written + 1
    if bar then
      pcall(function()
        gma.gui.progress.settext(bar, string.format("%s (%d/%d)", name, i, #members))
        gma.gui.progress.set(bar, i)
      end)
    end
  end

  if bank.kind == "preset" then gma.cmd("Clear") end
  if bar then pcall(function() gma.gui.progress.stop(bar) end) end

  local rollback = string.format("Delete %s Thru %d", address(bank, first), last)
  say("готово: %d объектов. Откат — %s", written, rollback)

  local parts = { bank.key, tostring(first), set.key }
  if bank.param then
    parts[#parts + 1] = num(bank.param.field == "size" and size or speed)
  end
  if prefix ~= "" then parts[#parts + 1] = prefix end

  msg(PLUGIN .. " — готово", string.format(
    "Банк «%s», набор «%s».\nЗаписано %d объектов:\n%s Thru %d\n\n" ..
    "Откат одной командой:\n%s\n\n" ..
    "Повторить:\nSetVar $%s \"%s\" ; Plugin \"%s\"",
    bank.title, set.title, written, address(bank, first), last,
    rollback, ARG_VAR, table.concat(parts, " "), PLUGIN))
end

-- ─── Разбор аргумента ───────────────────────────────────────────────────────

local function usageText()
  local lines = {
    'SetVar $' .. ARG_VAR .. ' "<банк> <номер> [набор] [число] [префикс…]"',
    'Plugin "' .. PLUGIN .. '"',
    "",
  }
  for _, b in ipairs(BANKS) do
    local dest = (b.kind == "effect") and "пул Effect" or ("пул пресетов " .. b.pool)
    local p = b.param and (" [" .. b.param.name .. ", по умолч. " ..
                           tostring(b.param.default) .. "]") or ""
    lines[#lines + 1] = string.format("  %-8s %s · %s%s", b.key, dest, b.title, p)
  end
  local more = {
    "",
    'Значения list и help вместо банка — список банков и эта подсказка.',
    "",
    "Нечисловые токены разбираются по типу, порядок между ними любой.",
    "ЧИСЛА ПОЗИЦИОННЫ: первое — номер объекта, второе — параметр банка.",
  }
  for _, l in ipairs(more) do lines[#lines + 1] = l end
  return table.concat(lines, "\n")
end

local function listText()
  local out = {}
  for _, b in ipairs(BANKS) do
    local dest = (b.kind == "effect")
      and string.format("Effect %d.x", EFFECT_POOL)
      or  string.format("Preset %d.x", b.pool)
    out[#out + 1] = string.format("%s — %s\n   %s, умолч. номер %d%s",
      b.key, b.title, dest, b.defaultFirst,
      b.needsSelection and ", ТРЕБУЕТ ВЫБОРКИ" or "")
    local sets = {}
    for _, s in ipairs(b.sets) do
      sets[#sets + 1] = string.format("%s (%d)", s.key, #s.members)
    end
    out[#out + 1] = "   наборы: " .. table.concat(sets, ", ")
    out[#out + 1] = ""
  end
  return table.concat(out, "\n")
end

local function parseArgument(argument)
  if argument == nil or argument == "" then return nil end
  local tokens = {}
  for w in tostring(argument):gmatch("%S+") do tokens[#tokens + 1] = w end
  if #tokens == 0 then return nil end

  local head = string.lower(tokens[1])
  if head == "help" or head == "?" then return { mode = "help" } end
  if head == "list" then return { mode = "list" } end

  local bank = bankByKey(head)
  if not bank then
    return { mode = "error",
             why = "первым идёт банк (" .. bankKeyList() .. ") либо list, help" }
  end

  -- Нечисловые токены разбираются по типу; числа позиционны между собой:
  -- два числа по виду не различить, а угадывание пишется в пул.
  local first, set, value, prefixParts = nil, nil, nil, {}
  for i = 2, #tokens do
    local t = tokens[i]
    local asSet = setByKey(bank, t)
    local asNum = tonumber(t)
    if asSet and not set then
      set = asSet
    elseif asNum and not first then
      if asNum < 1 or asNum ~= math.floor(asNum) then
        return { mode = "error", why = "номер объекта должен быть целым больше нуля" }
      end
      first = asNum
    elseif asNum and bank.param and not value then
      if asNum < bank.param.min or asNum > bank.param.max then
        return { mode = "error", why = string.format("%s: допустимо от %s до %s",
                 bank.param.name, tostring(bank.param.min), tostring(bank.param.max)) }
      end
      value = asNum
    else
      prefixParts[#prefixParts + 1] = t
    end
  end

  local task = {
    mode = "create", bank = bank,
    first = first or bank.defaultFirst,
    set = set or setByKey(bank, bank.defaultSet) or bank.sets[1],
    prefix = table.concat(prefixParts, " "),
    size = 1, speed = DEFAULT_SPEED,
  }
  if bank.param then
    if bank.param.field == "size" then
      task.size = value or bank.param.default
    else
      task.speed = value or bank.param.default
    end
  end
  return task
end

-- ─── Точка входа ────────────────────────────────────────────────────────────

local function Main()
  -- Аргумент: пользовательская переменная, как принято в MA2. Не задана —
  -- спрашиваем строкой: рich-диалога с полями в MA2 Lua нет.
  local argument = nil
  pcall(function() argument = gma.user.getvar(ARG_VAR) end)

  if argument == nil or argument == "" then
    local ok, res = pcall(function()
      return gma.textinput(PLUGIN .. ": банк номер набор [число]", "color 101 full")
    end)
    if ok then argument = res end
  end

  local task = parseArgument(argument)

  if task == nil then
    msg(PLUGIN, "Аргумент не задан.\n\n" .. usageText())
    return
  end

  if task.mode == "help" then msg(PLUGIN .. " — синтаксис", usageText()); return end
  if task.mode == "list" then msg(PLUGIN .. " — банки", listText()); return end

  if task.mode == "error" then
    say("аргумент не разобран: %s", task.why)
    msg(PLUGIN .. " — аргумент не разобран", task.why .. "\n\n" .. usageText())
    return
  end

  createSet(task)
end

return Main
