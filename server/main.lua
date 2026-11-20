-- ta-radio サーバー側
-- 誰がどの無線番号にいるかはここで持つ。声の行き先は pma-voice に任せ、ここからは setPlayerRadio だけを呼ぶ
-- 一覧（表示名・ID・倒れているか）は、同じ番号の人にだけ送る。話しているかは pma-voice の通知をクライアントが拾う

local members = {} -- src → { ch = 番号, name = 表示名, cid = citizenid, seq = 参加の順番 }
local downs = {} -- src → 倒れているか（qbx_medical が載せる state bag の isDead）
local lastAction = {} -- src → 最後に参加・抜けるをした時刻（ミリ秒）
local joining = {} -- src → いま setPlayerRadio を呼んでいる最中か（その間の state bag の変化は参加の処理が見る）
local seq = 0

-- ================== 入力の検査 ==================

-- 文字を整える。制御文字・改行と、GTA やチャットの記法に使う文字（~ ^ < >）を除き、上限で切る（ta-nametag と同じ）
local function cleanText(value, max)
    if type(value) ~= 'string' then return '' end
    local s = value:gsub('%c', ' '):gsub('~[%w_]*~', ''):gsub('<[^<>]*>', ''):gsub('%^%d', ''):gsub('[~%^<>]', '')
    s = s:gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
    local len = utf8.len(s)
    if not len then return '' end -- 壊れた UTF-8 は受け取らない
    if len > max then s = s:sub(1, utf8.offset(s, max + 1) - 1):gsub(' $', '') end
    return s
end

-- 無線番号を数にする。数字と小数点以外の文字（16 進数の 0x、指数の e など）は受け取らない
local function parseChannel(value)
    if type(value) == 'number' then value = tostring(value) end
    if type(value) ~= 'string' then return nil end
    value = value:gsub('%s', '')
    if not (value:match('^%d+$') or value:match('^%d+%.%d*$')) then return nil end
    local n = tonumber(value)
    if not n then return nil end
    n = math.floor(n * 100 + 0.5) / 100
    if n < Config.MinChannel or n > Config.MaxChannel then return nil end
    return n
end

-- 102.0 → "102"、102.5 → "102.5"、102.25 → "102.25"
local function formatChannel(ch)
    if ch == math.floor(ch) then return ('%d'):format(ch) end
    local s = ('%.2f'):format(ch):gsub('0$', '')
    return s
end

local function listHas(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

-- 使える人を決めた番号か。決まりが無ければ誰でも使える
local function canUse(src, ch)
    local rule = Config.RestrictedChannels[math.floor(ch)]
    if not rule then return true end
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return false end
    local data = player.PlayerData
    if rule.type == 'job' then
        local job = data.job or {}
        return listHas(rule.names, job.name) and (not rule.onDuty or job.onduty == true)
    elseif rule.type == 'gang' then
        return listHas(rule.names, (data.gang or {}).name)
    end
    return false
end

local function hasItem(src)
    local count = exports.ox_inventory:GetItemCount(src, Config.Item)
    return (tonumber(count) or 0) > 0
end

local function isDown(src)
    if downs[src] ~= nil then return downs[src] end
    local state = Player(src).state
    return state ~= nil and state.isDead == true
end

-- ================== 一覧を送る ==================

local function channelList(ch)
    local list = {}
    for src, m in pairs(members) do
        if m.ch == ch then list[#list + 1] = { id = src, name = m.name, down = isDown(src), seq = m.seq } end
    end
    table.sort(list, function(a, b) return a.seq < b.seq end)
    for _, v in ipairs(list) do v.seq = nil end
    return list
end

local function broadcast(ch)
    local list = channelList(ch)
    local payload = { channel = formatChannel(ch), members = list }
    for _, v in ipairs(list) do
        TriggerClientEvent('ta-radio:client:list', v.id, payload)
    end
end

-- ================== DB ==================

local function loadProfile(cid)
    local ok, row = pcall(MySQL.single.await,
        'SELECT display_name, last_channel FROM ta_radio_profiles WHERE citizenid = ?', { cid })
    if ok and row then return row end
    return nil
end

local function saveProfile(cid, name, ch)
    local ok, err = pcall(MySQL.query.await, [[
        INSERT INTO ta_radio_profiles (citizenid, display_name, last_channel) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE display_name = VALUES(display_name), last_channel = VALUES(last_channel)
    ]], { cid, name, formatChannel(ch) })
    if not ok then print(('[ta-radio] 表示名を保存できませんでした: %s'):format(tostring(err))) end
    return ok
end

-- ================== 参加と抜ける ==================

-- reason はクライアントに出す通知。nil なら出さない。dropped は切断（pma-voice が自分で片付ける）
local function leave(src, reason, dropped)
    local m = members[src]
    if not m then return false end
    -- 先に消す。setPlayerRadio が state bag を変えたとき、下のハンドラーがもう一度抜けさせないように
    members[src] = nil
    downs[src] = nil
    if not dropped then
        exports['pma-voice']:setPlayerRadio(src, 0)
        TriggerClientEvent('ta-radio:client:left', src, reason)
    end
    broadcast(m.ch)
    return true
end

local function fail(message, field) return { ok = false, message = message, field = field } end

local function tooFast(src)
    local now = GetGameTimer()
    if lastAction[src] and now - lastAction[src] < Config.Cooldown * 1000 then return true end
    lastAction[src] = now
    return false
end

lib.callback.register('ta-radio:profile', function(src)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return fail('キャラクターが読み込まれていません') end
    if not hasItem(src) then return fail('無線を持っていません') end
    local data = player.PlayerData
    local row = loadProfile(data.citizenid)
    local charName = cleanText(('%s %s'):format(data.charinfo.firstname or '', data.charinfo.lastname or ''), Config.MaxName)
    local m = members[src]
    return {
        ok = true,
        id = src,
        name = (row and row.display_name ~= '' and row.display_name) or charName,
        channel = m and formatChannel(m.ch) or (row and row.last_channel) or '',
        onRadio = m ~= nil,
        limits = { name = Config.MaxName, min = Config.MinChannel, max = Config.MaxChannel },
    }
end)

lib.callback.register('ta-radio:join', function(src, input)
    input = type(input) == 'table' and input or {}
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return fail('キャラクターが読み込まれていません') end
    if not hasItem(src) then return fail('無線を持っていません') end
    if isDown(src) then return fail('倒れている間は無線を合わせられません') end

    local name = cleanText(input.name, Config.MaxName)
    if name == '' then return fail('表示名を入れてください', 'name') end
    local ch = parseChannel(input.channel)
    if not ch then
        return fail(('無線番号は %s〜%s で入れてください（小数は 2 桁まで）'):format(Config.MinChannel, Config.MaxChannel), 'channel')
    end
    if not canUse(src, ch) then return fail(('無線 %s は決まった人しか使えません'):format(formatChannel(ch)), 'channel') end
    if tooFast(src) then return fail('少し待ってからもう一度どうぞ') end

    local cid = player.PlayerData.citizenid
    local old = members[src]

    -- 同じ番号のまま表示名だけ変えたとき
    if old and old.ch == ch then
        old.name = name
        saveProfile(cid, name, ch)
        broadcast(ch)
        return { ok = true, channel = formatChannel(ch), renamed = true }
    end

    seq = seq + 1
    members[src] = { ch = ch, name = name, cid = cid, seq = seq }
    downs[src] = Player(src).state.isDead == true
    joining[src] = true
    exports['pma-voice']:setPlayerRadio(src, ch)
    joining[src] = nil

    -- pma-voice に断られたとき（無線が無効・ほかのリソースの検査など）は元に戻す
    if Player(src).state.radioChannel ~= ch then
        members[src] = nil
        downs[src] = nil
        if old then broadcast(old.ch) end
        TriggerClientEvent('ta-radio:client:left', src, nil)
        return fail('この無線番号には合わせられませんでした', 'channel')
    end

    saveProfile(cid, name, ch)
    if old then broadcast(old.ch) end
    broadcast(ch)
    return { ok = true, channel = formatChannel(ch) }
end)

lib.callback.register('ta-radio:leave', function(src)
    if not members[src] then return fail('無線に入っていません') end
    if tooFast(src) then return fail('少し待ってからもう一度どうぞ') end
    leave(src, nil)
    return { ok = true }
end)

-- クライアントが「無線が鞄から無くなった」と言ってきたとき。本当に無いかはここで確かめる
RegisterNetEvent('ta-radio:server:check', function()
    local src = source
    if members[src] and not hasItem(src) then leave(src, '無線を手放したので、無線から抜けました') end
end)

-- ================== 状態の変化 ==================

-- 倒れた・起き上がった（qbx_medical は LAST_STAND と DEAD のどちらでも isDead を true にする）
-- ハンドラーが呼ばれた時点では、まだ新しい値が入っていないことがあるので、渡された値を使う
AddStateBagChangeHandler('isDead', nil, function(bagName, _, value)
    local src = GetPlayerFromStateBagName(bagName)
    if not src or src == 0 or not members[src] then return end
    local down = value == true
    if downs[src] == down then return end
    downs[src] = down
    broadcast(members[src].ch)
end)

-- ほかのリソースが無線番号を変えたとき（pma-voice の state bag）。一覧からは外す
AddStateBagChangeHandler('radioChannel', nil, function(bagName, _, value)
    local src = GetPlayerFromStateBagName(bagName)
    if not src or src == 0 or joining[src] then return end
    local m = members[src]
    if not m or tonumber(value) == m.ch then return end
    members[src] = nil
    downs[src] = nil
    TriggerClientEvent('ta-radio:client:left', src, '無線番号がほかから変えられたので、一覧を閉じました')
    broadcast(m.ch)
end)

AddEventHandler('playerDropped', function()
    local src = source
    leave(src, nil, true)
    lastAction[src] = nil
end)

-- キャラクター選択に戻ったとき
AddEventHandler('qbx_core:server:playerLoggedOut', function(src)
    leave(src, nil)
end)

-- ================== 決まった番号の検査を pma-voice にも渡す ==================
-- ta-radio を通さずに pma-voice のイベントで直接合わせた人も、決まりに従わせる（整数の番号だけ）

local function registerChecks()
    for ch in pairs(Config.RestrictedChannels) do
        local channel = ch
        exports['pma-voice']:addChannelCheck(channel, function(src)
            return canUse(src, channel)
        end)
    end
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        registerChecks()
        CreateThread(function()
            MySQL.query.await([[
                CREATE TABLE IF NOT EXISTS ta_radio_profiles (
                    citizenid VARCHAR(50) NOT NULL PRIMARY KEY,
                    display_name VARCHAR(64) NOT NULL,
                    last_channel VARCHAR(16) NOT NULL DEFAULT '',
                    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
                )
            ]])
        end)
    elseif resource == 'pma-voice' then
        -- pma-voice が再起動すると、検査も各自の番号も消える。入れ直す
        registerChecks()
        for src, m in pairs(members) do
            exports['pma-voice']:setPlayerRadio(src, m.ch)
        end
    end
end)

-- ta-radio を止めるときは、入っている人を無線から抜く（一覧が消えて声だけ残るのを防ぐ）
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for src in pairs(members) do
        exports['pma-voice']:setPlayerRadio(src, 0)
    end
end)

-- ================== 持っているかの見回り ==================

CreateThread(function()
    while true do
        Wait(Config.ItemCheckInterval * 1000)
        local gone = {}
        for src in pairs(members) do
            if not hasItem(src) then gone[#gone + 1] = src end
        end
        for _, src in ipairs(gone) do
            leave(src, '無線を手放したので、無線から抜けました')
        end
    end
end)
