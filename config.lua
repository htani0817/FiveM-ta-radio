Config = {}

-- 使うと入力画面が開くアイテム（ox_inventory の items.lua で client.event を 'ta-radio:client:use' にする）
Config.Item = 'radio'

-- 画面の大きさの倍率（画面の高さ / 1080 × この値）。一覧と無線機の両方に掛かる
Config.UiScale = 1.0

-- 右の一覧の置き場所。top は画面の上からの位置（画面の高さに対する割合）、right は右端からの距離（px、1080 基準）
Config.List = {
    top = 0.22,
    right = 24,
}

-- 合わせられる無線番号。小数は 2 桁まで（それより細かい値は四捨五入する）
Config.MinChannel = 1
Config.MaxChannel = 500

-- 表示名の文字数の上限（全角も半角も 1 文字）
Config.MaxName = 16

-- 右の一覧に並べる人数の上限。超えた分は「ほか N 人」とだけ出す
Config.MaxRows = 12

-- 参加・抜けるの操作は何秒に 1 回まで
Config.Cooldown = 1

-- 無線を持っているかをサーバーで確かめる間隔（秒）。手放した人は無線から抜ける
Config.ItemCheckInterval = 10

-- 右の一覧を出す・隠すコマンド（無線からは抜けない）
Config.ToggleCommand = 'radiolist'

-- 無線で話すときの決まり。ta-radio に入っているあいだ、この値を使う
Config.Talk = {
    -- 押している間だけ送信するキーの既定値（FiveM のキー設定の「ta-radio」に出る。各自が変えられる）
    -- キーの名前: https://docs.fivem.net/docs/game-references/input-mapper-parameter-ids/keyboard/
    key = 'LMENU',
    keyLabel = '左 Alt', -- 無線機の横に出す案内
    clicks = true, -- 送信の始めと終わりに「ピッ」と鳴らす
    clickVolume = 10, -- その音量（0〜100）
    volume = 60, -- ほかの人の声の大きさ（0〜100）
    animation = true, -- 送信中に肩の無線に手を当てる
}

-- 無線機を操作したときの電子音（開く・ボタン・合わせた・失敗・閉じる）
Config.Beep = {
    enabled = true,
    volume = 0.25, -- 0〜1
}

-- 無線機を開いている間、右手に無線機（stream/ta_radio.ydr）を持つ
-- 付け方は mm_radio が純正の prop_cs_hand_radio に使っていた値。ta_radio は純正と軸・原点を揃えて作ったので同じ値で持てる
Config.Prop = {
    enabled = true,
    model = 'ta_radio',
    bone = 57005, -- SKEL_R_Hand
    pos = vec3(0.14, 0.01, -0.02),
    rot = vec3(110.0, 120.0, -15.0),
    dict = 'cellphone@',
    anim = 'cellphone_text_read_base',
}

-- 使える人を決めた無線番号。小数の番号は整数の部分で判定する（12.5 は 12 の決まりに従う）
-- type は 'job' か 'gang'。onDuty = true なら出勤中だけ
-- 既定値は mm_radio の RestrictedChannels と同じ
Config.RestrictedChannels = {
    [1] = { type = 'job', names = { 'police', 'ambulance' }, onDuty = true },
    [2] = { type = 'job', names = { 'police', 'ambulance' }, onDuty = true },
    [3] = { type = 'job', names = { 'police', 'ambulance' }, onDuty = true },
    [4] = { type = 'job', names = { 'police', 'ambulance' }, onDuty = true },
    [5] = { type = 'job', names = { 'police', 'ambulance' }, onDuty = true },
    [6] = { type = 'job', names = { 'police', 'ambulance' }, onDuty = true },
    [7] = { type = 'job', names = { 'police', 'ambulance' }, onDuty = true },
    [8] = { type = 'job', names = { 'police', 'ambulance' }, onDuty = true },
    [9] = { type = 'job', names = { 'police', 'ambulance' }, onDuty = true },
    [10] = { type = 'job', names = { 'police', 'ambulance' }, onDuty = true },
    [420] = { type = 'gang', names = { 'ballas' } },
    [421] = { type = 'gang', names = { 'lostmc' } },
    [422] = { type = 'gang', names = { 'vagos' } },
}
