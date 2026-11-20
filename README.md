---
title: ta-radio（無線）
date: 2026-11-20
tags:
  - コーディング/fivem
status: 疑似環境のテスト・画面の描画・モデルの読み込み直しは確認済み。検証サーバーに導入済み。FiveM 実機は未確認
aliases:
  - ta-radio
related:
  - "[[FiveM-Script/README|FiveM-Script 目次]]"
  - "[[ta-nametag/README|ta-nametag]]"
---

# ta-radio（無線）

Qbox サーバー向けの無線。無線アイテムを使うと、表示名と無線番号を入れる画面が開く。合わせると画面の右側中央に、同じ番号にいる人の一覧が出る。一覧には無線番号、人数、表示名、ID が並び、倒れた人の行は赤くなって表示名に赤い横線が引かれる。話している人の行は琥珀色に光る。

声のやり取りは、サーバーに入っている pma-voice の無線をそのまま使う。ta-radio は「誰がどの番号にいるか」と画面、それに無線機のモデルを受け持つ。今の mm_radio と置き換える前提で作った。

無線機は Blender で作った自作のモデル（`ta_radio`）。入力画面を開いている間は右手に持ち、ox_inventory のアイコンも同じモデルから描いた（[[#無線機のモデル]]）。

> [!warning] FiveM 実機ではまだ確かめていない
> 疑似環境のテスト（サーバー 70 件・クライアント 46 件）、ブラウザでの画面の確認、書き出したモデルの読み込み直しまでは済んでいる。検証サーバーには入れたが、ゲームの中での確認はこれから。導入の手順は [[#導入（mm_radio からの置き換え）]] にある。

## 使い方

| 操作 | 内容 |
| --- | --- |
| 無線アイテムを使う | 入力画面を開き、右手に無線機を持って画面を見る格好をする（閉じるとしまう）。表示名は前に使った名前（初めてならキャラクター名）、無線番号は今の番号か前回の番号が入っている |
| 合わせる・`Enter` | その番号に入る。右側中央に一覧が出る。同じ番号のまま表示名だけ変えることもできる |
| 抜ける | 無線から抜ける。一覧も消える（無線に入っているときだけ出るボタン） |
| `Esc` | 何も変えずに閉じる |
| 左 Alt（押している間） | 無線で話す。キーは pma-voice の設定で、各自が FiveM のキー設定で変えられる |
| `/radiolist` | 一覧を隠す・出す。無線からは抜けない |

- 表示名は 16 文字まで。キャラクターごとに DB に残り、次に開いたときに入っている
- 無線番号は 1〜500。小数は 2 桁まで使える（`102.5`、`12.35` など）。3 桁目は四捨五入する
- 警察・救急の 1〜10 番と、ギャングの 420〜422 番は決まった人しか入れない（mm_radio と同じ決まり。[[#設定]]）
- 倒れている間は入力画面を開けない。開いたまま倒れると閉じる
- 無線アイテムを手放すと、自動で無線から抜ける

## 画面

方向は「業務用の無線機の液晶と、夜勤の指令台」。ゲームの画面の端で、誰がいて誰が話しているかを一目で読めることを優先した。土台は [[ta-nametag/README|ta-nametag]] と同じ落ち着いた灰色で、色を持つのは「話している人」の琥珀色と「倒れた人」の赤だけ。

- **一覧**（右側中央）: 上に「無線番号」と大きな番号、右に人数。その下に 1 人 1 行で、左から信号の棒・表示名・ID。並び順は入った順。自分の行には小さく「自分」と付く
- **話している人**: 行の背景が琥珀色になり、左端に琥珀色の線、信号の棒も琥珀色に点く
- **倒れた人**: 行の背景が赤くなり、表示名に赤い横線が引かれる。信号の棒も赤
- **人が多いとき**: 12 人まで並べ、残りは「ほか 4人」のように 1 行で出す（`Config.MaxRows`）
- **入力画面**（中央）: 表示名・無線番号の欄、合わせる・抜けるのボタン。下に送信キーと `Esc` をキーの形で出す。サーバーに断られたときは、理由をボタンの上に赤で出し、原因の欄の枠を赤くする
- ポーズメニューを開いている間は一覧を消す
- 大きさは画面の高さに合わせる（1080 で 1 倍。`Config.UiScale` でさらに掛ける）

## 無線機のモデル

![[ta-radio/blender/preview/three_quarter.png|360]]

手に持つ業務用の無線機。正面に琥珀色に光る液晶（無線番号と、画面の一覧と同じ 3 本の信号の棒）、操作ボタン 3 つ、スピーカー。上にゴムのアンテナとつまみ 2 つ、琥珀色の表示灯。右の側面に送信ボタン、背面に電池とベルトクリップ。形と寸法は [[ta-radio/blender/PARTS|部品表]] にまとめた。

| 項目 | 値 |
| --- | --- |
| ファイル | `stream/ta_radio.ydr`（テクスチャ埋め込み）、`stream/ta_radio.ytyp` |
| 大きさ | 幅 6.2 cm・奥行き 3.4 cm・本体の高さ 16.2 cm（アンテナの先まで 25.7 cm） |
| 三角形 | 956（上限 2,000。純正の prop_cs_hand_radio は 440） |
| テクスチャ | 512×512 の 1 枚（DXT1）。本体用と、光る面（液晶・表示灯）用の 2 材質 |
| コリジョン | 本体を包む箱 1 つ（手に持つ間はクライアントで当たりを切る） |
| アイコン | `install/radio.png`（256×256・背景は透明） |

**手への付け方。** 軸と原点を純正の `prop_cs_hand_radio`（mm_radio が手に持たせていた）に合わせて作った。正面は -Y、上は +Z、原点は本体の中で上から約 4 cm。純正は GTA V のファイルから取り出して Blender で測った（取り出したファイルはリソースに入れていない）。だから mm_radio の付け方（右手の骨 57005、位置 `0.14, 0.01, -0.02`、回転 `110, 120, -15`、`cellphone@` の `cellphone_text_read_base`）をそのまま使っている。ずれていたら `Config.Prop` で直す。

**作り直し方。** 手順は anymachine の「部品表を先に決める → 1 本のスクリプトで組む → 検証で締める」。参照画像の生成（外部の有料サービス）は使っていない。

```sh
cd blender
py -3.13 make_textures.py                                      # tex/ta_radio_atlas.dds と layout.json（Pillow は 3.13 に入っている）
"C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" -b --python build_model.py   # ../stream と ../install/radio.png、preview/
"C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" -b --python verify_model.py  # 読み込み直して比べる
```

- `build_model.py` は三角形の数と外形を部品表と比べ、上限を超えるか 1 mm より大きくずれると止まる。一度、アンテナの先が部品表より 2 mm 長かったのをこれで見つけて直した
- `verify_model.py` は書き出した ydr と ytyp を空の場面に読み込み直し、メッシュの数・三角形の数・外形・材質・埋め込みテクスチャ・archetype が書き出す前と同じかを確かめる。描画は `preview/reimport.png`
- `--factory-startup` を付けると Sollumz の依存（szio）が読めないので付けない

## 導入（mm_radio からの置き換え）

ta-radio と mm_radio は同じ `radio` アイテムを取り合うので、同時には使わない。

1. `ta-radio` フォルダ（`blender/` と `tests/` は要らない）を `resources/[voice]/` に置く。`[standalone]` は `[voice]` より先に起動するので、pma-voice と同じ `[voice]` がよい
2. `mm_radio` を `resources/[disabled]/` へ移す（消さない）
3. `resources/[ox]/ox_inventory/data/items.lua` の `radio` を次のように変える

    ```lua
    ['radio'] = {
        label = 'Radio',
        weight = 1000,
        allowArmed = true,
        consume = 0,
        client = {
            event = 'ta-radio:client:use'
        }
    },
    ```

4. アイコン `install/radio.png` を `resources/[ox]/ox_inventory/web/images/radio.png` に上書きする（今の絵は `radio.png.bak` などに退避しておく）
5. `server.cfg` で `ensure` する（`[voice]` に置いたなら、今の `ensure [voice]` で読まれる）。ox_lib・oxmysql・qbx_core・ox_inventory・pma-voice より後に起動する
6. DB の表 `ta_radio_profiles` は、初めて起動したときに自動で作る

> [!note] ox_inventory の改修
> `items.lua` の書き換えとアイコンの差し替えは、ox_inventory を上流から更新すると元に戻るので、そのときは入れ直す。元のアイコンは上書きする前に退避しておく。

## 設定

`config.lua` で変える。

| 項目 | 既定値 | 内容 |
| --- | --- | --- |
| `Item` | `'radio'` | 使うと入力画面が開くアイテム |
| `UiScale` | `1.0` | 画面の大きさの倍率 |
| `MinChannel` / `MaxChannel` | `1` / `500` | 合わせられる番号の範囲（mm_radio の上限と同じ） |
| `MaxName` | `16` | 表示名の文字数の上限 |
| `MaxRows` | `12` | 一覧に並べる人数の上限 |
| `Cooldown` | `1` | 合わせる・抜けるを受け付ける間隔（秒） |
| `ItemCheckInterval` | `10` | 無線を持っているかをサーバーで確かめる間隔（秒） |
| `ToggleCommand` | `'radiolist'` | 一覧を出す・隠すコマンド |
| `Prop` | 右手の骨 57005・mm_radio と同じ位置と回転 | 入力画面を開いている間に持つ無線機。`enabled = false` で持たない |
| `TalkKeyLabel` | `'左 Alt'` | 入力画面に出す送信キーの案内。キーそのものは `voice.cfg` の `voice_defaultRadio` |
| `RestrictedChannels` | 1〜10 は police・ambulance（出勤中だけ）、420 は ballas、421 は lostmc、422 は vagos | 使える人を決めた番号。小数の番号は整数の部分で判定する |

## 仕組み

- **誰がどこにいるか**はサーバーが持つ。合わせると、サーバーが入力を検査してから pma-voice の `setPlayerRadio` を呼ぶ。クライアントから pma-voice へ直接は合わせない
- **一覧**は、変化があるたびに同じ番号の人にだけ送る（入る・抜ける・表示名を変える・倒れる・起き上がる）
- **話しているか**は、pma-voice が同じ番号の全員に送る `pma-voice:setTalkingOnRadio` をクライアントで拾う。自分の行は `pma-voice:radioActive` ですぐ明るくする。サーバーとの通信は増えない
- **倒れたか**は、qbx_medical が載せる state bag の `isDead` をサーバーで見る（LAST_STAND と DEAD のどちらでも true）
- **決まった番号**は、ta-radio の検査に加えて pma-voice の `addChannelCheck` にも同じ判定を渡す。ta-radio を通さずに pma-voice のイベントで直接合わせようとしても断られる
- **持っているか**は、`ox_inventory:itemCount` で 0 になったときと、10 秒ごとの見回りの両方で確かめる
- ほかのリソースが pma-voice の番号を変えたときは、一覧を閉じる（state bag の `radioChannel` を見る）
- pma-voice が再起動したら、入っている人の番号と決まった番号の検査を入れ直す。ta-radio を止めるときは、全員を無線から抜く

## テスト

`tests/` に ta-nametag と同じ方法のテストがある。

```sh
npm i fengari luaparse          # 作業用のフォルダで（NODE_PATH をそこへ向ける）
node tests/check.js .           # Lua の構文・未定義のグローバル、BOM と CR
node tests/run-test.js . tests/test-server.lua
node tests/run-test.js . tests/test-client.lua
node tests/ui-shot.js "file:///<このフォルダ>/html/index.html#list" <出力先> "wait:700,shot:list" 1920x1080
```

- `test-server.lua`（70 件）: 表の作成、入力画面の初期値（初めての人・保存済み・持っていない人）、参加と一覧の配信（参加の順）、番号の検査（範囲外・16 進数・指数・負の数・小数の四捨五入）、表示名の検査（空・記法・タグ・上限・壊れた UTF-8）、連打、決まった番号（出勤中・退勤中・ギャング・小数・pma-voice 側の検査）、pma-voice に断られたとき、表示名だけ変える、別の番号へ移る、倒れた・起き上がった、抜ける、手放した、見回り、ほかのリソースが番号を変えた、切断、ログアウト、DB の失敗、pma-voice の再起動、停止
- `test-client.lua`（46 件）: 入力画面の開閉（倒れている・ポーズメニュー・サーバーが断った・応答なし）、開くと無線機を右手に付けて格好をする・閉じる／倒れる／止めるとしまう・モデルが読めなくても開く、合わせる前に pma-voice の無線を有効にする、断られたら開いたまま、一覧に自分の ID を付ける、話している（ほかの人・自分）、`/radiolist`、ポーズメニュー中は消す、開いたまま倒れたら閉じる、無線が無くなったらサーバーに確かめさせる、抜ける、無線に入っていないときは何も送らない、停止
- `ui-shot.js`: `#list`（話している人と倒れた人）、`#many`（16 人）、`#long`（長い表示名）、`#form`、`#formOn`（参加中）、`#formError`（決まった番号で断られた）、`#formEmpty` を 1920×1080 と 1280×720 で撮って確かめた。ブラウザで `html/index.html#場面` を開くと見本のデータで出る（ゲームの中では動かない）

## 実機で確かめること

- 入力画面を開いたとき、無線機が右手に収まっているか（向きと位置。ずれていたら `Config.Prop`）。ほかの人にも見えるか
- 液晶と表示灯が夜に光って見えるか
- インベントリのアイコンが暗い枠の上で見えるか

- 無線アイテムを使って入力画面が開くか（`items.lua` の書き換え）
- 2 人以上で同じ番号に入り、声が届くか。話している人の行が光るか（自分の行も）
- 倒れたとき（LAST_STAND）に、ほかの人の一覧で赤くなり横線が付くか。起き上がると戻るか
- 一覧が右側中央で、ほかの HUD（qbx_hud・pma-voice の表示・ta-navhud など）と重ならないか
- 無線を捨てる・渡すと無線から抜けるか
- 警察の 1〜10 番に、出勤中の警察だけが入れるか

## 既知の制約

- 無線は 1 人 1 番号まで（pma-voice の仕様）
- 決まった番号に入ったあとで退勤しても、自動では抜けない（mm_radio と同じ）
- pma-voice 側の検査は整数の番号だけ。`3.5` のような小数の番号は、ta-radio を通さず pma-voice のイベントで直接合わせると決まりをすり抜けられる（ta-radio の入力画面からは整数の部分で判定するので入れない）
- mm_radio の電池・妨害装置（jammer）・お気に入りは作っていない
- 声の音量の調整は無い（pma-voice の既定 `voice_defaultRadioVolume` のまま）
