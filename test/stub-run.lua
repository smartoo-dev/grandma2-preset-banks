--[[
  Заглушки API grandMA2 для прогона плагина без консоли.

  Подменяется таблица gma: cmd, echo, feedback, gui.msgbox, gui.confirm,
  gui.progress.*, show.getobj.handle, user.getvar, textinput.

  Проверяет поток управления, разбор аргумента, выбор банка и текст команд —
  но НЕ поведение консоли: сюда не входит ни разбор команд, ни движок
  эффектов, ни патч, ни то, окажется ли эффект шаблоном. Зелёный прогон
  означает «код не падает и шлёт то, что задумано», а не «на консоли работает».

  Запуск из корня проекта:
    lua5.4 test/stub-run.lua                 все сценарии подряд
    lua5.4 test/stub-run.lua <имя сценария>  один сценарий
]]

local SCENARIOS = {
  { name = "color",   arg = "color 101 full",   note = "пресеты: 24 цвета, Store /u", dump = true },
  { name = "dim",     arg = "dim 1 basic",      note = "эффекты: 5 диммерных", dump = true },
  { name = "pos",     arg = "pos 10 basic 20",  note = "эффекты: относительные, размах 20°", dump = true },
  { name = "colorfx", arg = "colorfx 20 basic", note = "эффекты: три линии по каналам", dump = true },

  { name = "defaults", arg = "dim",                     note = "только банк → умолчания" },
  { name = "swapped",  arg = "pos shapes Show 40 30",   note = "нечисловые в любом порядке, числа позиционны" },
  { name = "numorder", arg = "pos 30 501",              note = "501 как размах → отказ" },
  { name = "badbank",  arg = "gobo 1",                  note = "неизвестный банк → подсказка" },
  { name = "help",     arg = "help",                    note = "синтаксис" },
  { name = "list",     arg = "list",                    note = "список банков" },
  { name = "novar",    arg = nil,                       note = "переменная не задана → textinput" },

  { name = "busy",     arg = "dim 1 basic",   busy = true,    note = "диапазон занят → подтверждение" },
  { name = "refuse",   arg = "color 101 basic", refuse = true, note = "отказ на подтверждении → ноль записей" },
  { name = "missing",  arg = "dim 1 basic",   missing = true, note = "контрольный объект не создан → остановка" },
}

local function run(sc)
  local cmds, store, dlg = {}, {}, 0

  -- Полная заглушка таблицы gma.
  gma = {
    echo = function() end,
    feedback = function() end,
    sleep = function() end,
    cmd = function(s)
      cmds[#cmds + 1] = s
      -- Запоминаем созданные объекты, чтобы exists() их видел.
      local pool, idx = s:match("^Store Preset (%d+)%.(%d+)")
      if not pool then pool, idx = s:match("^Store Effect (%d+)%.(%d+)") end
      if pool and idx and not s:match("%.%d+%.%d+") and not sc.missing then
        store[pool .. "." .. idx] = true
      end
    end,
    textinput = function(title, old)
      print("  [textinput] " .. title .. "  (по умолчанию: " .. tostring(old) .. ")")
      return "colorfx 20 basic 90"
    end,
    user = {
      getvar = function(_) return sc.arg end,
      setvar = function() end,
    },
    gui = {
      msgbox = function(title, message)
        dlg = dlg + 1
        print(string.format("  [msgbox %d] %s", dlg, title))
        if message then print("    | " .. message:gsub("\n", "\n    | ")) end
      end,
      confirm = function(title, message)
        dlg = dlg + 1
        local answer = not sc.refuse
        print(string.format("  [confirm %d] %s  → %s", dlg, title,
                            answer and "да" or "НЕТ"))
        if message then print("    | " .. message:gsub("\n", "\n    | ")) end
        return answer or nil
      end,
      progress = {
        start = function() return 1 end,
        stop = function() end,
        settext = function() end,
        setrange = function() end,
        set = function() end,
      },
    },
    show = {
      getobj = {
        handle = function(a)
          if type(a) == "number" then return true end
          local pool, idx = a:match("^Preset (%d+)%.(%d+)$")
          if not pool then pool, idx = a:match("^Effect (%d+)%.(%d+)$") end
          if not pool then return nil end
          if sc.busy and tonumber(idx) <= 110 then return 42 end
          return store[pool .. "." .. idx] and 42 or nil
        end,
      },
    },
  }

  print(string.format("\n######## %s — %s ########", sc.name, sc.note))
  local Main = dofile("presetbanks.lua")
  local ok, err = pcall(Main)
  if not ok then print("  ОШИБКА: " .. tostring(err)); return false end

  print(string.format("  --- команд отправлено: %d ---", #cmds))
  if sc.dump then
    -- Печатаем команды первого элемента: до строки, повторяющей по форме
    -- самую первую (числа заменяются на #) — это начало второго элемента.
    local function shape(s) return (s:gsub("%-?%d+%.?%d*", "#")) end
    print("  первый элемент, все его команды:")
    local head = shape(cmds[1] or "")
    for i = 1, #cmds do
      if i > 1 and shape(cmds[i]) == head then break end
      print("    " .. cmds[i])
    end
  elseif #cmds > 0 then
    for i = 1, math.min(3, #cmds) do print("    " .. cmds[i]) end
    if #cmds > 4 then print("    …") end
    if #cmds > 3 then print("    " .. cmds[#cmds]) end
  end
  return true
end

local only = arg[1]
local failed, ran = 0, 0
for _, sc in ipairs(SCENARIOS) do
  if not only or only == sc.name then
    ran = ran + 1
    if not run(sc) then failed = failed + 1 end
  end
end
print(string.format("\nСценариев: %d, с ошибкой Lua: %d", ran, failed))
os.exit(failed == 0 and 0 or 1)
