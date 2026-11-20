-- server/main.lua を FiveM の疑似環境で動かすテスト（fengari / Lua 5.3）
-- qbx_core・ox_inventory・pma-voice・oxmysql は、使っている export と関数だけを本物の引数に合わせて疑似する
local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1 else fail = fail + 1; io.write('NG: ' .. msg .. '\n') end
end

function vec3(x, y, z) return { x = x, y = y, z = z } end
assert(load(SOURCES['config.lua']))()

-- ---- FiveM ----
local handlers, netEvents, bagHandlers, threads, printed = {}, {}, {}, {}, {}
function AddEventHandler(name, fn) handlers[name] = fn end
function RegisterNetEvent(name, fn) netEvents[name] = fn end
function CreateThread(fn) threads[#threads + 1] = fn end
function Wait() end
function print(...) printed[#printed + 1] = table.concat({ ... }, ' ') end
function GetCurrentResourceName() return 'ta-radio' end
local now = 100000
function GetGameTimer() return now end
source = nil

local states = {} -- src → state bag
function Player(src)
  states[src] = states[src] or {}
  return { state = states[src] }
end
function AddStateBagChangeHandler(key, _, fn) bagHandlers[key] = fn end
function GetPlayerFromStateBagName(bag) return tonumber(bag:match('^player:(%d+)$')) or 0 end
local function setBag(src, key, value)
  -- 本物と同じく、ハンドラーは値が入る前に呼ばれる
  if bagHandlers[key] then bagHandlers[key]('player:' .. src, key, value) end
  Player(src).state[key] = value
end

local sent = {} -- TriggerClientEvent の記録
function TriggerClientEvent(name, target, ...) sent[#sent + 1] = { name = name, target = target, args = { ... } } end
local function clearSent() sent = {} end
local function sentTo(name, target)
  local out = {}
  for _, s in ipairs(sent) do if s.name == name and s.target == target then out[#out + 1] = s end end
  return out
end
local function member(list, id)
  for _, m in ipairs(list and list.members or {}) do if m.id == id then return m end end
end
local function lastList(target)
  local l = sentTo('ta-radio:client:list', target)
  return l[#l] and l[#l].args[1]
end

-- ---- oxmysql ----
local rows, dbFail, created = {}, false, false
MySQL = {
  single = { await = function(_, p) return rows[p[1]] end },
  query = { await = function(q, p)
    if q:find('CREATE TABLE') then created = true; return {} end
    if dbFail then error('DB が落ちている') end
    rows[p[1]] = { display_name = p[2], last_channel = p[3] }
    return {}
  end },
}

-- ---- qbx_core・ox_inventory・pma-voice ----
local players, items = {}, {}
local function addPlayer(src, cid, first, last, job, gang)
  players[src] = { PlayerData = {
    source = src, citizenid = cid,
    charinfo = { firstname = first, lastname = last },
    job = job or { name = 'unemployed', onduty = false },
    gang = gang or { name = 'none' },
  } }
  items[src] = 1
end
local checks, pmaCalls, pmaReject = {}, {}, {}
exports = {
  qbx_core = { GetPlayer = function(_, src) return players[src] end },
  ox_inventory = { GetItemCount = function(_, src, item) assert(item == 'radio'); return items[src] or 0 end },
  ['pma-voice'] = {
    addChannelCheck = function(_, ch, fn) checks[ch] = fn end,
    setPlayerRadio = function(_, src, ch)
      pmaCalls[#pmaCalls + 1] = { src = src, ch = ch }
      -- 本物と同じく、検査に落ちたら 0 にする
      local allowed = ch == 0 or ((not checks[ch] or checks[ch](src)) and not pmaReject[ch])
      setBag(src, 'radioChannel', allowed and ch or 0)
    end,
  },
}

-- ---- ox_lib ----
local callbacks = {}
lib = { callback = { register = function(name, fn) callbacks[name] = fn end } }
local function call(name, src, ...) now = now + 5000; return callbacks[name](src, ...) end

-- ================== 起動 ==================

assert(load(SOURCES['server/main.lua']))()
local patrol = threads[1] -- 読み込んだときに始まる見回り
ok(#threads == 1, '読み込み時のスレッドは見回りだけ')
handlers.onResourceStart('ta-radio')
threads[2]() -- 表を作る
ok(created, '起動時に表を作る')
ok(checks[1] and checks[420] and not checks[11], '決まった番号の検査を pma-voice に渡す')

addPlayer(1, 'AAA001', '早瀬', '晴')
addPlayer(2, 'AAA002', '山城', '透')
addPlayer(3, 'AAA003', '北条', 'ちひろ', { name = 'police', onduty = true })
addPlayer(4, 'AAA004', 'Mika', 'K', { name = 'police', onduty = false }, { name = 'ballas' })

-- ================== 入力画面の初期値 ==================

local p = call('ta-radio:profile', 1)
ok(p.ok and p.name == '早瀬 晴' and p.channel == '' and p.onRadio == false, '初めての人はキャラクター名・番号は空')
ok(p.limits.name == 16 and p.limits.min == 1 and p.limits.max == 500, '上限を返す')
items[2] = 0
ok(call('ta-radio:profile', 2).ok == false, '無線を持っていなければ開かない')
items[2] = 1
ok(call('ta-radio:profile', 99).ok == false, 'キャラクターが無ければ開かない')

-- ================== 参加 ==================

clearSent()
local r = call('ta-radio:join', 1, { name = '  ハル  ', channel = '102.5' })
ok(r.ok and r.channel == '102.5', '102.5 に合わせられる')
ok(states[1].radioChannel == 102.5, 'pma-voice に番号を渡す')
local l = lastList(1)
ok(l and l.channel == '102.5' and #l.members == 1 and l.members[1].name == 'ハル' and l.members[1].id == 1, '一覧に自分が出る（前後の空白は削る）')
ok(rows.AAA001 and rows.AAA001.display_name == 'ハル' and rows.AAA001.last_channel == '102.5', '表示名と番号を保存する')

p = call('ta-radio:profile', 1)
ok(p.name == 'ハル' and p.channel == '102.5' and p.onRadio == true, '次に開くと保存した表示名と今の番号が入る')

clearSent()
r = call('ta-radio:join', 2, { name = '透', channel = 102.50 })
ok(r.ok, '数で送っても合わせられる')
l = lastList(1)
ok(l and #l.members == 2 and l.members[1].id == 1 and l.members[2].id == 2, '先にいた人にも新しい一覧が届く（参加の順）')
ok(lastList(2) and #lastList(2).members == 2, '入った人にも届く')

-- 番号の検査
local bad = { '0', '501', 'abc', '0x10', '1e2', '-5', '', '12.3.4', ' ' }
for _, v in ipairs(bad) do
  r = call('ta-radio:join', 3, { name = 'ちひろ', channel = v })
  ok(r.ok == false and r.field == 'channel', '無線番号「' .. v .. '」は断る')
end
r = call('ta-radio:join', 3, { name = 'ちひろ', channel = '12.345' })
ok(r.ok and r.channel == '12.35', '小数 3 桁目は四捨五入する')
r = call('ta-radio:join', 3, { name = 'ちひろ', channel = '12.' })
ok(r.ok and r.channel == '12', '「12.」は 12')
call('ta-radio:leave', 3)

-- 表示名の検査
r = call('ta-radio:join', 3, { name = '   ', channel = '50' })
ok(r.ok == false and r.field == 'name', '空の表示名は断る')
r = call('ta-radio:join', 3, { name = '~r~<b>赤</b>^1字', channel = '50' })
ok(r.ok and rows.AAA003.display_name == '赤字', '色の記法とタグは除く')
r = call('ta-radio:join', 3, { name = 'あいうえおかきくけこさしすせそたちつ', channel = '50' })
ok(r.ok and utf8.len(rows.AAA003.display_name) == 16, '表示名は 16 文字で切る')
r = call('ta-radio:join', 3, { name = '壊れ' .. string.char(0xff), channel = '50' })
ok(r.ok == false, '壊れた UTF-8 は断る')
call('ta-radio:leave', 3)

-- 連打
now = now + 5000
r = callbacks['ta-radio:join'](3, { name = 'ちひろ', channel = '60' })
ok(r.ok, '1 回目は通る')
r = callbacks['ta-radio:join'](3, { name = 'ちひろ', channel = '61' })
ok(r.ok == false, '1 秒以内の 2 回目は断る')
call('ta-radio:leave', 3)

-- ================== 決まった番号 ==================

r = call('ta-radio:join', 2, { name = '透', channel = '3' })
ok(r.ok == false and r.field == 'channel', '警察の番号に一般の人は入れない')
ok(states[2].radioChannel == 102.5, '断られても元の番号のまま')
r = call('ta-radio:join', 3, { name = 'ちひろ', channel = '3.5' })
ok(r.ok, '出勤中の警察は 3.5 に入れる（整数の部分で判定）')
r = call('ta-radio:join', 4, { name = 'Mika', channel = '3' })
ok(r.ok == false, '退勤中の警察は入れない')
r = call('ta-radio:join', 4, { name = 'Mika', channel = '420' })
ok(r.ok, 'ballas は 420 に入れる')
ok(checks[3](2) == false and checks[3](3) == true, 'pma-voice 側の検査も同じ判定')
call('ta-radio:leave', 3)
call('ta-radio:leave', 4)

-- pma-voice が断ったとき
pmaReject[77] = true
clearSent()
r = call('ta-radio:join', 3, { name = 'ちひろ', channel = '77' })
ok(r.ok == false and r.field == 'channel', 'pma-voice に断られたら失敗を返す')
ok(#sentTo('ta-radio:client:left', 3) == 1 and sentTo('ta-radio:client:left', 3)[1].args[1] == nil, '一覧を閉じさせる（通知は二重に出さない）')
pmaReject[77] = nil

-- ================== 表示名だけ変える・番号を移る ==================

clearSent()
local before = #pmaCalls
r = call('ta-radio:join', 1, { name = 'ハル改', channel = '102.5' })
ok(r.ok and r.renamed, '同じ番号なら表示名だけ変える')
ok(#pmaCalls == before, 'pma-voice は呼ばない')
ok(lastList(2).members[1].name == 'ハル改', 'ほかの人の一覧も変わる')

clearSent()
r = call('ta-radio:join', 1, { name = 'ハル改', channel = '200' })
ok(r.ok, '別の番号へ移れる')
ok(#lastList(2).members == 1 and lastList(2).members[1].id == 2, '元の番号の一覧から消える')
ok(lastList(1).channel == '200' and #lastList(1).members == 1, '新しい番号の一覧が届く')
ok(#sentTo('ta-radio:client:left', 1) == 0, '移っただけでは一覧を閉じない')
r = call('ta-radio:join', 1, { name = 'ハル改', channel = '102.5' })
ok(r.ok and lastList(1).members[2].id == 1, '戻ってきた人は一覧の後ろに付く')

-- ================== 倒れた・起き上がった ==================

clearSent()
setBag(2, 'isDead', true)
l = lastList(1)
ok(member(l, 2) and member(l, 2).down == true and member(l, 1).down == false, '倒れたら同じ番号の人に down が届く')
clearSent()
setBag(2, 'isDead', true)
ok(#sent == 0, '同じ値なら送らない')
r = call('ta-radio:join', 2, { name = '透', channel = '300' })
ok(r.ok == false, '倒れている間は番号を変えられない')
setBag(2, 'isDead', false)
ok(member(lastList(1), 2).down == false, '起き上がったら戻る')
clearSent()
setBag(4, 'isDead', true)
ok(#sent == 0, '無線に入っていない人が倒れても何も送らない')
states[4].isDead = false

-- ================== 抜ける ==================

clearSent()
r = call('ta-radio:leave', 2)
ok(r.ok and states[2].radioChannel == 0, '抜けると pma-voice の番号を 0 にする')
ok(#sentTo('ta-radio:client:left', 2) == 1, '本人の一覧を閉じる')
ok(#lastList(1).members == 1, '残った人の一覧から消える')
ok(call('ta-radio:leave', 2).ok == false, '入っていなければ抜けられない')

-- 無線を手放した
call('ta-radio:join', 2, { name = '透', channel = '102.5' })
items[2] = 0
clearSent()
local s0 = source
source = 2
netEvents['ta-radio:server:check']()
source = s0
ok(#sentTo('ta-radio:client:left', 2) == 1 and sentTo('ta-radio:client:left', 2)[1].args[1] ~= nil, '手放したら抜けて通知する')
items[2] = 1

-- 見回り
call('ta-radio:join', 2, { name = '透', channel = '102.5' })
items[2] = 0
clearSent()
-- 見回りは while true なので、2 回目の Wait で止めて 1 周だけ動かす
local waits = 0
local oldWait = Wait
Wait = function() waits = waits + 1; if waits > 1 then error('止める') end end
pcall(patrol)
Wait = oldWait
ok(waits == 2, '見回りが 1 周した')
ok(#sentTo('ta-radio:client:left', 2) == 1 and states[2].radioChannel == 0, '見回りで手放した人を抜けさせる')
ok(#lastList(1).members == 1, '残った人の一覧から消える')
items[2] = 1

-- ほかのリソースが番号を変えた
call('ta-radio:join', 2, { name = '透', channel = '102.5' })
clearSent()
setBag(2, 'radioChannel', 5)
ok(#sentTo('ta-radio:client:left', 2) == 1, 'ほかから番号を変えられたら一覧を閉じる')
ok(#lastList(1).members == 1, '残った人の一覧から消える')

-- 切断
call('ta-radio:join', 2, { name = '透', channel = '102.5' })
clearSent()
before = #pmaCalls
source = 2
handlers.playerDropped()
source = nil
ok(#pmaCalls == before, '切断では pma-voice を呼ばない（pma-voice が片付ける）')
ok(#lastList(1).members == 1, '切断した人は一覧から消える')

-- キャラクター選択へ戻る
call('ta-radio:join', 3, { name = 'ちひろ', channel = '102.5' })
clearSent()
handlers['qbx_core:server:playerLoggedOut'](3)
ok(states[3].radioChannel == 0 and #lastList(1).members == 1, 'ログアウトで抜ける')

-- ================== DB の失敗 ==================

dbFail = true
r = call('ta-radio:join', 3, { name = 'ちひろ', channel = '102.5' })
ok(r.ok, 'DB に保存できなくても無線には入れる')
ok(printed[#printed] and printed[#printed]:find('保存できません'), 'ログに残す')
dbFail = false

-- ================== pma-voice の再起動・ta-radio の停止 ==================

before = #pmaCalls
handlers.onResourceStart('pma-voice')
local again = 0
for i = before + 1, #pmaCalls do if pmaCalls[i].ch ~= 0 then again = again + 1 end end
ok(again == 2, 'pma-voice が再起動したら入っている人の番号を入れ直す')
handlers.onResourceStop('ta-radio')
ok(states[1].radioChannel == 0 and states[3].radioChannel == 0, '止めるときは全員を無線から抜く')

io.write(('server: %d 件 OK, %d 件 NG\n'):format(pass, fail))
if fail > 0 then error('失敗あり') end
