-- ta-radio クライアント側
-- アイテムを使うと、右下から無線機が出てきて、その画面で表示名と無線番号を入れる。合わせてよいかの判定はすべてサーバー側
-- 右の一覧はサーバーから届いた中身をそのまま NUI に渡す。話しているかは pma-voice の通知を拾う
-- 声の送受信は pma-voice に任せるが、送信キー・音量・クリック音などの決まりは Config.Talk（ta-radio 側）で決める

local formOpen = false
local busy = false
local onRadio = false
local hidden = false -- /radiolist で隠したか
local paused = false

local function notify(msg, kind)
    exports.qbx_core:Notify(msg, kind or 'inform')
end

local function nui(action, data)
    data = data or {}
    data.action = action
    data.scale = Config.UiScale
    data.list = Config.List
    data.beep = Config.Beep
    SendNUIMessage(data)
end

-- ================== 無線で話すときの決まり（Config.Talk） ==================

-- 無線に入ったときに pma-voice へ渡す。mm_radio が切ったまま残したクリック音も、ここで戻る
local function applyTalkSettings()
    local t = Config.Talk
    local voice = exports['pma-voice']
    pcall(function() voice:setVoiceProperty('radioEnabled', true) end)
    pcall(function() voice:setVoiceProperty('micClicks', t.clicks == true) end)
    pcall(function() voice:setMicClickOnVolume(t.clickVolume) end)
    pcall(function() voice:setMicClickOffVolume(t.clickVolume) end)
    pcall(function() voice:setRadioVolume(t.volume) end)
    pcall(function() voice:setDisableRadioAnim(t.animation ~= true) end)
end

-- 送信キーは ta-radio のキー設定として出す。押している間だけ pma-voice の送信を動かす
RegisterCommand('+ta_radio_talk', function()
    if onRadio then ExecuteCommand('+radiotalk') end
end, false)
RegisterCommand('-ta_radio_talk', function()
    ExecuteCommand('-radiotalk')
end, false)
RegisterKeyMapping('+ta_radio_talk', '無線で話す（押している間）', 'keyboard', Config.Talk.key)

local function isDown()
    return LocalPlayer.state.isDead == true or IsEntityDead(cache.ped)
end

-- ================== 手に持つ無線機 ==================

local prop = nil

-- 入力画面を開いている間だけ、右手に ta_radio を持って画面を見る格好をする（ほかの人にも見える）
local function holdRadio()
    local p = Config.Prop
    if not p or not p.enabled or prop then return end
    local model = joaat(p.model)
    -- モデルが読めないとき（stream が入っていないなど）は持たずに続ける
    if not pcall(lib.requestModel, model, 3000) then return end
    if pcall(lib.requestAnimDict, p.dict, 3000) then
        TaskPlayAnim(cache.ped, p.dict, p.anim, 2.0, 3.0, -1, 49, 0, false, false, false)
    end
    local c = GetEntityCoords(cache.ped)
    prop = CreateObject(model, c.x, c.y, c.z + 0.2, true, true, false)
    SetEntityCollision(prop, false, false)
    AttachEntityToEntity(prop, cache.ped, GetPedBoneIndex(cache.ped, p.bone), p.pos.x, p.pos.y, p.pos.z,
        p.rot.x, p.rot.y, p.rot.z, true, true, false, true, 2, true)
    SetModelAsNoLongerNeeded(model)
end

local function putAwayRadio()
    if not prop then return end
    StopAnimTask(cache.ped, Config.Prop.dict, Config.Prop.anim, 1.0)
    if DoesEntityExist(prop) then DeleteEntity(prop) end
    prop = nil
end

-- ================== 無線機の画面 ==================

-- result は NUI の音と動きに使う（'joined' 合わせた・'left' 抜けた・nil 閉じただけ）
local function closeForm(result)
    if not formOpen then return end
    formOpen = false
    SetNuiFocus(false, false)
    nui('closeForm', { result = result })
    putAwayRadio()
end

local function openForm()
    if formOpen or busy or IsPauseMenuActive() then return end
    if isDown() then
        notify('倒れている間は無線を使えません', 'error')
        return
    end
    busy = true
    local res = lib.callback.await('ta-radio:profile', false)
    busy = false
    if not res or not res.ok then
        notify(res and res.message or '応答がありません', 'error')
        return
    end
    formOpen = true
    SetNuiFocus(true, true)
    holdRadio()
    nui('openForm', {
        name = res.name,
        channel = res.channel,
        onRadio = res.onRadio,
        limits = res.limits,
        talkKey = Config.Talk.keyLabel,
    })
end

-- ox_inventory の items.lua で、無線の client.event をこのイベントにする
RegisterNetEvent('ta-radio:client:use', openForm)
exports('openForm', openForm)

RegisterNUICallback('join', function(data, cb)
    if busy or not formOpen then return cb({ ok = false, busy = true }) end
    data = type(data) == 'table' and data or {}
    busy = true
    applyTalkSettings()
    local res = lib.callback.await('ta-radio:join', false, { name = data.name, channel = data.channel })
    busy = false
    if res and res.ok then
        closeForm('joined')
        notify(res.renamed and '表示名を変えました' or ('無線 %s に合わせました'):format(res.channel), 'success')
    end
    cb(res or { ok = false, message = '応答がありません' })
end)

RegisterNUICallback('leave', function(_, cb)
    if busy or not formOpen then return cb({ ok = false, busy = true }) end
    busy = true
    local res = lib.callback.await('ta-radio:leave', false)
    busy = false
    if res and res.ok then
        closeForm('left')
        notify('無線から抜けました', 'inform')
    end
    cb(res or { ok = false, message = '応答がありません' })
end)

RegisterNUICallback('close', function(_, cb)
    closeForm()
    cb({})
end)

-- ================== 右の一覧 ==================

RegisterNetEvent('ta-radio:client:list', function(payload)
    if type(payload) ~= 'table' then return end
    -- 入った直後（再接続や pma-voice の再起動のあとも）に決まりを渡し直す
    if not onRadio then applyTalkSettings() end
    onRadio = true
    payload.self = cache.serverId
    payload.maxRows = Config.MaxRows
    payload.hidden = hidden
    nui('list', payload)
end)

RegisterNetEvent('ta-radio:client:left', function(reason)
    onRadio = false
    nui('left')
    if reason then notify(reason, 'inform') end
end)

-- pma-voice は、同じ番号の全員（話した本人も含む）にこのイベントを送る。pma-voice 側の処理はそのまま動く
RegisterNetEvent('pma-voice:setTalkingOnRadio', function(id, enabled)
    if onRadio then nui('talk', { id = id, on = enabled == true }) end
end)

-- 自分が送信キーを押した・離した。サーバーを往復する前に、自分の行をすぐ明るくする
AddEventHandler('pma-voice:radioActive', function(enabled)
    if onRadio then nui('talk', { id = cache.serverId, on = enabled == true }) end
end)

-- 鞄から無線が無くなった。本当に無いかはサーバーが確かめる
AddEventHandler('ox_inventory:itemCount', function(name, count)
    if onRadio and name == Config.Item and (tonumber(count) or 0) <= 0 then
        TriggerServerEvent('ta-radio:server:check')
    end
end)

RegisterCommand(Config.ToggleCommand, function()
    if not onRadio then
        notify('無線に入っていません', 'error')
        return
    end
    hidden = not hidden
    nui('visible', { hidden = hidden })
    notify(hidden and '無線の一覧を隠しました' or '無線の一覧を出しました', 'inform')
end, false)

-- ポーズメニューの間は一覧を消す。無線機の画面を開いたまま倒れたら閉じる
CreateThread(function()
    while true do
        Wait((onRadio or formOpen) and 250 or 1000)
        local p = IsPauseMenuActive()
        if p ~= paused then
            paused = p
            nui('pause', { on = p })
        end
        if formOpen and isDown() then closeForm() end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if formOpen then SetNuiFocus(false, false) end
    putAwayRadio()
end)
