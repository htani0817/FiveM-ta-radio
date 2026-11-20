-- client/main.lua を FiveM の疑似環境で動かすテスト（fengari / Lua 5.3）
local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1 else fail = fail + 1; io.write('NG: ' .. msg .. '\n') end
end

function vec3(x, y, z) return { x = x, y = y, z = z } end
assert(load(SOURCES['config.lua']))()

-- ---- FiveM ----
local handlers, netEvents, nuiCbs, commands, threads = {}, {}, {}, {}, {}
function AddEventHandler(name, fn) handlers[name] = fn end
function RegisterNetEvent(name, fn) netEvents[name] = fn end
function RegisterNUICallback(name, fn) nuiCbs[name] = fn end
function RegisterCommand(name, fn) commands[name] = fn end
function CreateThread(fn) threads[#threads + 1] = fn end
local keymaps, executed = {}, {}
function RegisterKeyMapping(cmd, desc, kind, key) keymaps[cmd] = { desc = desc, kind = kind, key = key } end
function ExecuteCommand(cmd) executed[#executed + 1] = cmd end
function Wait() end
function GetCurrentResourceName() return 'ta-radio' end

local msgs, focus, serverEvents = {}, { false, false }, {}
function SendNUIMessage(d) msgs[#msgs + 1] = d end
function SetNuiFocus(a, b) focus = { a, b } end
function TriggerServerEvent(name, ...) serverEvents[#serverEvents + 1] = { name = name, args = { ... } } end
local pauseMenu, pedDead = false, false
function IsPauseMenuActive() return pauseMenu end
function IsEntityDead() return pedDead end
LocalPlayer = { state = { isDead = false } }
cache = { ped = 100, serverId = 12 }

-- 手に持つ無線機
local objects, nextObj, anims, attached, modelOk = {}, 500, {}, {}, true
function joaat(s) return 'hash:' .. s end
function GetEntityCoords() return { x = 1.0, y = 2.0, z = 3.0 } end
function CreateObject(model, x, y, z, net) nextObj = nextObj + 1; objects[nextObj] = { model = model, net = net }; return nextObj end
function SetEntityCollision(e, on) objects[e].collision = on end
function GetPedBoneIndex(_, bone) return 'bone:' .. bone end
function AttachEntityToEntity(e, ped, bone, x, y, z, rx, ry, rz) attached[e] = { ped = ped, bone = bone, pos = { x, y, z }, rot = { rx, ry, rz } } end
function SetModelAsNoLongerNeeded() end
function TaskPlayAnim(_, dict, anim, _, _, _, flag) anims[#anims + 1] = { dict = dict, anim = anim, flag = flag, on = true } end
function StopAnimTask(_, dict, anim) anims[#anims + 1] = { dict = dict, anim = anim, on = false } end
function DoesEntityExist(e) return objects[e] ~= nil end
function DeleteEntity(e) objects[e] = nil end
local function liveObjects()
  local n = 0
  for _ in pairs(objects) do n = n + 1 end
  return n
end

local function lastMsg(action)
  for i = #msgs, 1, -1 do if msgs[i].action == action then return msgs[i] end end
end
local function count(action)
  local n = 0
  for _, m in ipairs(msgs) do if m.action == action then n = n + 1 end end
  return n
end

-- ---- qbx_core・pma-voice・ox_lib ----
local notes, voiceProps = {}, {}
local exported = {}
exports = setmetatable({
  qbx_core = { Notify = function(_, msg, kind) notes[#notes + 1] = { msg = msg, kind = kind } end },
  ['pma-voice'] = {
    setVoiceProperty = function(_, k, v) voiceProps[k] = v end,
    setMicClickOnVolume = function(_, v) voiceProps.clickOn = v end,
    setMicClickOffVolume = function(_, v) voiceProps.clickOff = v end,
    setRadioVolume = function(_, v) voiceProps.volume = v end,
    setDisableRadioAnim = function(_, v) voiceProps.noAnim = v end,
  },
}, { __call = function(_, name, fn) exported[name] = fn end })

local replies, awaited = {}, {}
lib = {
  requestModel = function(m) if not modelOk then error('読めない') end; return m end,
  requestAnimDict = function(d) return d end,
  callback = { await = function(name, _, data)
  awaited[#awaited + 1] = { name = name, data = data }
  local r = replies[name]
  if type(r) == 'function' then return r(data) end
  return r
end },
}

local function nuiCall(name, data)
  local res
  nuiCbs[name](data or {}, function(r) res = r end)
  return res
end

-- ================== 読み込み ==================

assert(load(SOURCES['client/main.lua']))()
ok(netEvents['ta-radio:client:use'] ~= nil and exported.openForm ~= nil, 'アイテムのイベントと export を登録する')
ok(commands.radiolist ~= nil, '一覧を出す・隠すコマンドを登録する')
ok(keymaps['+ta_radio_talk'] and keymaps['+ta_radio_talk'].key == 'LMENU' and keymaps['+ta_radio_talk'].kind == 'keyboard', '送信キーを ta-radio のキー設定として出す（既定は Config.Talk.key）')
commands['+ta_radio_talk']()
ok(#executed == 0, '無線に入っていなければ送信しない')

-- ================== 入力画面 ==================

replies['ta-radio:profile'] = { ok = true, name = 'ハル', channel = '102.5', onRadio = false, limits = { name = 16, min = 1, max = 500 } }
netEvents['ta-radio:client:use']()
local m = lastMsg('openForm')
ok(m and m.name == 'ハル' and m.channel == '102.5' and m.talkKey == '左 Alt', '保存した表示名と番号で入力画面を開く')
ok(m.list and m.list.top == 0.22 and m.beep and m.beep.volume == 0.25, '一覧の置き場所と電子音の設定を NUI に渡す')
ok(focus[1] == true and focus[2] == true, 'マウスとキーを NUI に渡す')

-- 手に持つ無線機
local held = next(objects)
ok(held and objects[held].model == 'hash:ta_radio' and objects[held].net == true, '入力画面を開くと ta_radio を作る（ほかの人にも見える）')
ok(objects[held].collision == false, '当たりは切る')
ok(attached[held] and attached[held].bone == 'bone:57005' and attached[held].pos[1] == 0.14 and attached[held].rot[1] == 110.0, '右手に mm_radio と同じ位置で付ける')
ok(anims[#anims].dict == 'cellphone@' and anims[#anims].anim == 'cellphone_text_read_base' and anims[#anims].flag == 49 and anims[#anims].on, '画面を見る格好をする（上半身だけ）')

local before = #msgs
netEvents['ta-radio:client:use']()
ok(#msgs == before, '開いている間にもう一度使っても開き直さない')

-- 閉じる
nuiCall('close')
ok(focus[1] == false and lastMsg('closeForm'), 'Esc で閉じる')
ok(liveObjects() == 0 and anims[#anims].on == false, '閉じたら無線機をしまい、格好を戻す')
ok(#anims == 2, '開き直しを断ったときに 2 つ目の無線機を作らない')

-- モデルが読めなくても入力画面は開く
modelOk = false
replies['ta-radio:profile'] = { ok = true, name = 'ハル', channel = '', onRadio = false, limits = {} }
netEvents['ta-radio:client:use']()
ok(focus[1] == true and liveObjects() == 0, 'モデルが読めないときは持たずに開く')
nuiCall('close')
ok(focus[1] == false, '持っていなくても閉じられる')
modelOk = true

-- 倒れている・ポーズメニュー・サーバーが断った
LocalPlayer.state.isDead = true
netEvents['ta-radio:client:use']()
ok(notes[#notes].kind == 'error' and focus[1] == false, '倒れている間は開かない')
LocalPlayer.state.isDead = false
pauseMenu = true
before = #msgs
netEvents['ta-radio:client:use']()
ok(#msgs == before, 'ポーズメニュー中は開かない')
pauseMenu = false
replies['ta-radio:profile'] = { ok = false, message = '無線を持っていません' }
netEvents['ta-radio:client:use']()
ok(notes[#notes].msg == '無線を持っていません' and focus[1] == false, 'サーバーが断ったら理由を出す')
replies['ta-radio:profile'] = nil
netEvents['ta-radio:client:use']()
ok(notes[#notes].msg == '応答がありません', '応答が無ければそう出す')

-- 参加
replies['ta-radio:profile'] = { ok = true, name = 'ハル', channel = '', onRadio = false, limits = {} }
netEvents['ta-radio:client:use']()
replies['ta-radio:join'] = { ok = false, message = '無線 3 は決まった人しか使えません', field = 'channel' }
local res = nuiCall('join', { name = 'ハル', channel = '3' })
ok(res.ok == false and res.field == 'channel' and focus[1] == true, '断られたら画面を開いたまま理由を返す')
ok(voiceProps.radioEnabled == true, '合わせる前に pma-voice の無線を有効にする')
ok(voiceProps.micClicks == true and voiceProps.clickOn == 10 and voiceProps.clickOff == 10, 'クリック音をオンにして音量を渡す（mm_radio が切ったままでも戻る）')
ok(voiceProps.volume == 60 and voiceProps.noAnim == false, '無線の音量と送信中の動作を Config.Talk から渡す')
ok(awaited[#awaited].data.channel == '3' and awaited[#awaited].data.name == 'ハル', '入力をそのままサーバーへ渡す')

replies['ta-radio:join'] = { ok = true, channel = '102.5' }
res = nuiCall('join', { name = 'ハル', channel = '102.5' })
ok(res.ok and focus[1] == false, '合わせたら閉じる')
ok(lastMsg('closeForm').result == 'joined', '合わせて閉じたことを NUI に伝える（音を変える）')
ok(notes[#notes].msg == '無線 102.5 に合わせました', '合わせた番号を知らせる')
res = nuiCall('join', { name = 'ハル', channel = '1' })
ok(res.busy, '閉じたあとの送信は受け付けない')

-- ================== 右の一覧 ==================

netEvents['ta-radio:client:list']({ channel = '102.5', members = { { id = 12, name = 'ハル', down = false }, { id = 4, name = '透', down = true } } })
m = lastMsg('list')
ok(m and m.self == 12 and m.maxRows == 12 and m.hidden == false and #m.members == 2, '一覧に自分の ID と上限を付けて渡す')

-- 送信キー
commands['+ta_radio_talk']()
commands['-ta_radio_talk']()
ok(executed[#executed - 1] == '+radiotalk' and executed[#executed] == '-radiotalk', '無線に入っていれば、押している間だけ pma-voice の送信を動かす')

-- 話している
netEvents['pma-voice:setTalkingOnRadio'](4, true)
m = lastMsg('talk')
ok(m and m.id == 4 and m.on == true, 'ほかの人が話し始めた')
handlers['pma-voice:radioActive'](true)
m = lastMsg('talk')
ok(m and m.id == 12 and m.on == true, '自分が送信キーを押した')
handlers['pma-voice:radioActive'](false)
ok(lastMsg('talk').on == false, '離した')

-- 隠す・出す
commands.radiolist()
ok(lastMsg('visible').hidden == true, '/radiolist で隠す')
netEvents['ta-radio:client:list']({ channel = '102.5', members = {} })
ok(lastMsg('list').hidden == true, '隠している間に一覧が来ても隠したまま')
commands.radiolist()
ok(lastMsg('visible').hidden == false, 'もう一度で出す')

-- ポーズメニューと、倒れたら入力画面を閉じる
local waits = 0
Wait = function() waits = waits + 1; if waits > 2 then error('止める') end end
pauseMenu = true
replies['ta-radio:profile'] = { ok = true, name = 'ハル', channel = '102.5', onRadio = true, limits = {} }
pcall(threads[1])
ok(lastMsg('pause') and lastMsg('pause').on == true, 'ポーズメニューの間は一覧を消す')
pauseMenu = false
waits = 0
pcall(threads[1])
ok(lastMsg('pause').on == false, '戻ったら出す')
netEvents['ta-radio:client:use']()
ok(focus[1] == true, '入力画面を開く')
pedDead = true
waits = 0
pcall(threads[1])
ok(focus[1] == false, '開いたまま倒れたら閉じる')
ok(liveObjects() == 0, '倒れたら無線機もしまう')
pedDead = false

-- 鞄から無線が無くなった
handlers['ox_inventory:itemCount']('phone', 0)
ok(#serverEvents == 0, 'ほかのアイテムでは何もしない')
handlers['ox_inventory:itemCount']('radio', 0)
ok(serverEvents[#serverEvents].name == 'ta-radio:server:check', '無線が 0 になったらサーバーに確かめさせる')

-- 抜ける
replies['ta-radio:profile'] = { ok = true, name = 'ハル', channel = '102.5', onRadio = true, limits = {} }
netEvents['ta-radio:client:use']()
replies['ta-radio:leave'] = { ok = true }
res = nuiCall('leave')
ok(res.ok and focus[1] == false and notes[#notes].msg == '無線から抜けました', '抜けるで閉じて知らせる')
ok(lastMsg('closeForm').result == 'left', '抜けて閉じたことを NUI に伝える')
netEvents['ta-radio:client:left']('無線を手放したので、無線から抜けました')
ok(lastMsg('left') and notes[#notes].msg:find('手放した'), 'サーバーから抜けさせられたら一覧を消して知らせる')
local n = #notes
netEvents['ta-radio:client:left'](nil)
ok(#notes == n, '理由が無ければ通知しない')

-- 抜けたあとは「話している」を送らない
before = count('talk')
netEvents['pma-voice:setTalkingOnRadio'](4, true)
handlers['pma-voice:radioActive'](true)
ok(count('talk') == before, '無線に入っていなければ送らない')
local ex = #executed
commands['+ta_radio_talk']()
ok(#executed == ex, '抜けたあとは送信キーを押しても送信しない')
commands.radiolist()
ok(notes[#notes].kind == 'error', '入っていなければ /radiolist は断る')
handlers['ox_inventory:itemCount']('radio', 0)
ok(serverEvents[#serverEvents].name == 'ta-radio:server:check' and #serverEvents == 1, '入っていなければ確かめさせない')

-- 止めたとき
replies['ta-radio:profile'] = { ok = true, name = 'ハル', channel = '', onRadio = false, limits = {} }
netEvents['ta-radio:client:use']()
handlers.onResourceStop('ta-radio')
ok(focus[1] == false, '止めたら NUI のフォーカスを返す')
ok(liveObjects() == 0, '止めたら無線機を消す')

io.write(('client: %d 件 OK, %d 件 NG\n'):format(pass, fail))
if fail > 0 then error('失敗あり') end
