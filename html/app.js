// ta-radio の NUI。右上寄りの一覧と、右下から出てくる無線機
'use strict';

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : null;
const $ = (id) => document.getElementById(id);
const chars = (s) => [...String(s || '')].length;

const state = {
    channel: '',
    members: [],
    self: 0,
    maxRows: 12,
    talking: new Set(),
    hidden: false,
    paused: false,
    onRadio: false,
    open: false,
    deviceOnRadio: false,
    limits: { name: 16, min: 1, max: 500 },
    sending: false,
};

function post(name, data) {
    if (!RES) return Promise.resolve(Sample.post(name, data || {}));
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    }).then((r) => r.json()).catch(() => null);
}

// ================== 大きさ・置き場所 ==================

let lastScale = 1;
function setScale(scale) {
    lastScale = Number(scale) || 1;
    const s = (window.innerHeight / 1080) * lastScale;
    document.documentElement.style.setProperty('--scale', String(Math.max(0.5, s)));
}

function setList(list) {
    if (!list) return;
    const root = document.documentElement.style;
    if (Number.isFinite(Number(list.top))) root.setProperty('--list-top', `${Number(list.top) * 100}vh`);
    if (Number.isFinite(Number(list.right))) root.setProperty('--list-right', `${Number(list.right)}px`);
}

// ================== 電子音 ==================
// 無線機らしい短い矩形波。音のファイルは使わず、その場で作る

const Beep = {
    ctx: null,
    enabled: true,
    volume: 0.25,
    set(cfg) {
        if (!cfg) return;
        this.enabled = cfg.enabled !== false;
        if (Number.isFinite(Number(cfg.volume))) this.volume = Math.min(1, Math.max(0, Number(cfg.volume)));
    },
    tone(freq, dur, at = 0) {
        if (!this.enabled || this.volume <= 0) return;
        try {
            this.ctx = this.ctx || new AudioContext();
            const t = this.ctx.currentTime + at;
            const osc = this.ctx.createOscillator();
            const gain = this.ctx.createGain();
            osc.type = 'square';
            osc.frequency.value = freq;
            // 矩形波は大きく聞こえるので 0.2 倍。始めと終わりを 5ms で絞り、ぷつっと鳴らないようにする
            const peak = this.volume * 0.2;
            gain.gain.setValueAtTime(0, t);
            gain.gain.linearRampToValueAtTime(peak, t + 0.005);
            gain.gain.setValueAtTime(peak, t + dur - 0.005);
            gain.gain.linearRampToValueAtTime(0, t + dur);
            osc.connect(gain).connect(this.ctx.destination);
            osc.start(t);
            osc.stop(t + dur + 0.01);
        } catch (e) { /* 音が出せない環境では鳴らさない */ }
    },
    open() { this.tone(1600, 0.05); this.tone(2100, 0.06, 0.07); },
    key() { this.tone(2400, 0.03); },
    ok() { this.tone(1800, 0.06); this.tone(2400, 0.09, 0.08); },
    error() { this.tone(440, 0.16); },
    close() { this.tone(2100, 0.05); this.tone(1500, 0.06, 0.07); },
};

// ================== 一覧 ==================
// 表示名はほかの人が入力した文字なので、必ず textContent で入れる

function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
}

function rowFor(m) {
    const li = el('li', 'row');
    li.dataset.id = String(m.id);
    const sig = el('span', 'sig');
    sig.setAttribute('aria-hidden', 'true');
    sig.append(el('i'), el('i'), el('i'));
    const name = el('span', 'row-name');
    name.append(el('span', 'row-text', m.name));
    if (m.id === state.self) name.append(el('span', 'row-self', '自分'));
    li.append(sig, name, el('span', 'row-id', String(m.id)));
    return li;
}

function paintRow(li, m) {
    li.classList.toggle('down', m.down === true);
    // 倒れた人は話せない（pma-voice が止める）。万一届いても赤を優先する
    li.classList.toggle('talk', m.down !== true && state.talking.has(m.id));
}

function renderList() {
    const hud = $('hud');
    hud.hidden = !state.onRadio || state.hidden;
    hud.classList.toggle('paused', state.paused);
    if (!state.onRadio) return;

    $('hudChannel').textContent = state.channel;
    $('hudCount').textContent = `${state.members.length}人`;

    const shown = state.members.slice(0, state.maxRows);
    $('hudList').replaceChildren(...shown.map((m) => {
        const li = rowFor(m);
        paintRow(li, m);
        return li;
    }));

    const rest = state.members.length - shown.length;
    $('hudMore').hidden = rest <= 0;
    $('hudMore').textContent = rest > 0 ? `ほか ${rest}人` : '';
}

// 話しているかだけが変わったときは、行を作り直さずにクラスだけ替える
function paintTalk(id) {
    const m = state.members.find((v) => v.id === id);
    const li = $('hudList').querySelector(`.row[data-id="${id}"]`);
    if (m && li) paintRow(li, m);
}

function onList(d) {
    state.onRadio = true;
    state.channel = String(d.channel || '');
    state.members = Array.isArray(d.members) ? d.members.map((m) => ({
        id: Number(m.id), name: String(m.name || ''), down: m.down === true,
    })) : [];
    state.self = Number(d.self) || 0;
    state.maxRows = Number(d.maxRows) || 12;
    if (typeof d.hidden === 'boolean') state.hidden = d.hidden;
    // 抜けた人の「話している」は消す
    const ids = new Set(state.members.map((m) => m.id));
    for (const id of [...state.talking]) if (!ids.has(id)) state.talking.delete(id);
    renderList();
}

function onLeft() {
    state.onRadio = false;
    state.members = [];
    state.talking.clear();
    renderList();
}

function onTalk(d) {
    const id = Number(d.id);
    if (d.on) state.talking.add(id); else state.talking.delete(id);
    paintTalk(id);
}

// ================== 無線機 ==================

function channelPattern(value) {
    return /^\d+(\.\d{0,2})?$/.test(value);
}

function updateCount() {
    const n = chars($('nameInput').value);
    $('nameCount').textContent = `${n}/${state.limits.name}`;
}

function message(text, kind, field) {
    const box = $('lcdMsg');
    box.textContent = text || '';
    box.classList.toggle('error', kind === 'error');
    $('nameInput').classList.toggle('invalid', field === 'name');
    $('channelInput').classList.toggle('invalid', field === 'channel');
}

function idleMessage() {
    message(`${state.limits.min}〜${state.limits.max}・小数は 2 桁まで`);
}

function setDeviceState(onRadio, channel) {
    state.deviceOnRadio = onRadio;
    $('lcdState').textContent = onRadio && channel ? `${channel} に参加中` : '待機中';
    $('soft1').textContent = onRadio ? '抜ける' : '';
    $('key1').disabled = !onRadio;
}

function openForm(d) {
    state.limits = Object.assign({ name: 16, min: 1, max: 500 }, d.limits || {});
    $('nameInput').value = String(d.name || '');
    $('channelInput').value = String(d.channel || '');
    $('talkKey').textContent = d.talkKey || '左 Alt';
    setDeviceState(d.onRadio === true, d.channel);
    idleMessage();
    updateCount();
    setSending(false);

    const device = $('device');
    device.hidden = false;
    document.body.classList.add('device-open');
    state.open = true;
    // hidden を外した次の描画で open を付け、下からせり上がらせる
    requestAnimationFrame(() => requestAnimationFrame(() => device.classList.add('open')));
    Beep.open();

    const first = $('nameInput').value ? $('channelInput') : $('nameInput');
    first.focus();
    first.select();
}

// result: 'joined' 合わせた・'left' 抜けた・それ以外は閉じただけ
function closeForm(d) {
    if (!state.open) return;
    state.open = false;
    const result = d && d.result;
    if (result === 'joined') Beep.ok(); else Beep.close();
    const device = $('device');
    device.classList.remove('open');
    document.body.classList.remove('device-open');
    if (document.activeElement) document.activeElement.blur();
    // 下がりきってから隠す（途中でまた開いたときは隠さない）
    setTimeout(() => { if (!state.open) device.hidden = true; }, 500);
}

function setSending(on) {
    state.sending = on;
    for (const id of ['key1', 'key2', 'key3']) $(id).classList.toggle('busy', on);
}

// 画面の側でも先に確かめる（最後の判定はサーバー）
function validate() {
    const name = $('nameInput').value.trim();
    const ch = $('channelInput').value.trim();
    if (!name) return ['表示名を入れてください', 'name'];
    if (chars(name) > state.limits.name) return [`表示名は ${state.limits.name} 文字までです`, 'name'];
    if (!ch) return ['無線番号を入れてください', 'channel'];
    const n = Number(ch);
    if (!channelPattern(ch) || n < state.limits.min || n > state.limits.max) {
        return [`無線番号は ${state.limits.min}〜${state.limits.max} です`, 'channel'];
    }
    return null;
}

function fail(res) {
    Beep.error();
    message((res && res.message) || '応答がありません', 'error', res && res.field);
}

async function submit() {
    if (state.sending || !state.open) return;
    Beep.key();
    const bad = validate();
    if (bad) return fail({ message: bad[0], field: bad[1] });
    message('合わせています…');
    setSending(true);
    const res = await post('join', { name: $('nameInput').value.trim(), channel: $('channelInput').value.trim() });
    setSending(false);
    if (res && res.busy) return;
    if (!res || !res.ok) fail(res);
}

async function leave() {
    if (state.sending || !state.open || !state.deviceOnRadio) return;
    Beep.key();
    setSending(true);
    const res = await post('leave', {});
    setSending(false);
    if (res && res.busy) return;
    if (!res || !res.ok) fail(res);
}

function requestClose() {
    if (!state.open) return;
    post('close', {});
}

$('lcd').addEventListener('submit', (e) => {
    e.preventDefault();
    submit();
});
$('key1').addEventListener('click', leave);
$('key2').addEventListener('click', () => { Beep.key(); requestClose(); });
$('key3').addEventListener('click', submit);
$('nameInput').addEventListener('input', () => { updateCount(); idleMessage(); });
$('channelInput').addEventListener('input', idleMessage);

window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && state.open) {
        e.preventDefault();
        requestClose();
    }
});

// ================== Lua からの指示 ==================

window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.scale != null) setScale(d.scale);
    setList(d.list);
    Beep.set(d.beep);
    switch (d.action) {
        case 'openForm': return openForm(d);
        case 'closeForm': return closeForm(d);
        case 'list': return onList(d);
        case 'left': return onLeft();
        case 'talk': return onTalk(d);
        case 'pause': state.paused = d.on === true; return renderList();
        case 'visible': state.hidden = d.hidden === true; return renderList();
        default: return undefined;
    }
});

window.addEventListener('resize', () => setScale(lastScale));

// ================== ブラウザで見るとき（FiveM の外）だけ ==================
// index.html#list のように、# の後ろで場面を選ぶ。ゲームの中では動かない

const Sample = {
    members: [
        { id: 12, name: '早瀬 晴', down: false },
        { id: 4, name: 'ハル', down: false },
        { id: 27, name: '山城 透', down: true },
        { id: 31, name: 'Mika_K', down: false },
        { id: 8, name: '北条 ちひろ', down: false },
    ],
    post(name, data) {
        if (name === 'join') {
            if (String(data.channel) === '3') return { ok: false, message: '無線 3 は決まった人しか使えません', field: 'channel' };
            closeForm({ result: 'joined' });
            onList({ channel: data.channel, members: [{ id: 12, name: data.name, down: false }, ...Sample.members.slice(1)], self: 12 });
            return { ok: true, channel: data.channel };
        }
        if (name === 'leave') { closeForm({ result: 'left' }); onLeft(); return { ok: true }; }
        if (name === 'close') { closeForm({}); return {}; }
        return null;
    },
    run(scene) {
        document.body.classList.add('sample');
        setScale(1);
        Beep.enabled = false;
        const list = (members) => onList({ channel: '102.5', members, self: 12, maxRows: 12 });
        const many = Array.from({ length: 16 }, (_, i) => ({ id: 40 + i, name: `隊員 ${i + 1}`, down: i === 5 }));
        const limits = { name: 16, min: 1, max: 500 };
        const scenes = {
            list: () => { list(Sample.members); onTalk({ id: 4, on: true }); },
            downSelf: () => onList({ channel: '500', members: [{ id: 1, name: 'TANI', down: true }], self: 1 }),
            many: () => { onList({ channel: '7', members: many, self: 40, maxRows: 12 }); onTalk({ id: 42, on: true }); },
            long: () => list([{ id: 112, name: 'とても長い表示名を入れたときの人', down: false }, ...Sample.members]),
            form: () => openForm({ name: '早瀬 晴', channel: '102.5', onRadio: false, limits }),
            formOn: () => {
                list(Sample.members);
                openForm({ name: '早瀬 晴', channel: '102.5', onRadio: true, limits });
            },
            formError: () => {
                openForm({ name: '早瀬 晴', channel: '3', onRadio: false, limits });
                setTimeout(submit, 600);
            },
            formEmpty: () => openForm({ name: '', channel: '', onRadio: false, limits }),
        };
        (scenes[scene] || scenes.list)();
    },
};

if (!RES && location.protocol === 'file:') Sample.run(location.hash.slice(1));
