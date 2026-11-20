// ta-radio の NUI。右側中央の一覧と、アイテムを使ったときの入力画面
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

let lastScale = 1;
function setScale(scale) {
    lastScale = Number(scale) || 1;
    const s = (window.innerHeight / 1080) * lastScale;
    document.documentElement.style.setProperty('--scale', String(Math.max(0.5, s)));
}

// ================== 右の一覧 ==================
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
    li.append(sig, el('span', 'row-name', m.name), el('span', 'row-id', String(m.id)));
    return li;
}

function paintRow(li, m) {
    li.classList.toggle('self', m.id === state.self);
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

    const list = $('hudList');
    const shown = state.members.slice(0, state.maxRows);
    list.replaceChildren(...shown.map((m) => {
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

// ================== 入力画面 ==================

function channelPattern(value) {
    return /^\d+(\.\d{0,2})?$/.test(value);
}

function updateCount() {
    const n = chars($('nameInput').value);
    const meta = $('nameCount');
    meta.textContent = `${n}/${state.limits.name}`;
    meta.classList.toggle('over', n > state.limits.name);
}

function showError(message, field) {
    const box = $('formError');
    box.hidden = !message;
    box.textContent = message || '';
    $('nameInput').classList.toggle('invalid', field === 'name');
    $('channelInput').classList.toggle('invalid', field === 'channel');
}

function setFormState(onRadio, channel) {
    const s = $('formState');
    s.replaceChildren();
    if (onRadio && channel) {
        s.append(el('b', null, channel), document.createTextNode(' に参加中'));
    }
    $('leaveBtn').hidden = !onRadio;
}

function openForm(d) {
    state.limits = Object.assign({ name: 16, min: 1, max: 500 }, d.limits || {});
    $('nameInput').value = String(d.name || '');
    $('channelInput').value = String(d.channel || '');
    $('channelHint').textContent = `${state.limits.min}〜${state.limits.max}。小数は 2 桁まで`;
    $('talkKey').textContent = d.talkKey || '左 Alt';
    setFormState(d.onRadio === true, d.channel);
    showError(null);
    updateCount();
    setSending(false);
    $('form').hidden = false;
    // 表示名が入っていれば番号へ、無ければ表示名へ
    const first = $('nameInput').value ? $('channelInput') : $('nameInput');
    first.focus();
    first.select();
}

function closeForm() {
    $('form').hidden = true;
    document.activeElement && document.activeElement.blur();
}

function setSending(on) {
    state.sending = on;
    $('joinBtn').disabled = on;
    $('leaveBtn').disabled = on;
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
        return [`無線番号は ${state.limits.min}〜${state.limits.max} で入れてください（小数は 2 桁まで）`, 'channel'];
    }
    return null;
}

async function submit() {
    if (state.sending) return;
    const bad = validate();
    if (bad) return showError(bad[0], bad[1]);
    showError(null);
    setSending(true);
    const res = await post('join', { name: $('nameInput').value.trim(), channel: $('channelInput').value.trim() });
    setSending(false);
    if (res && res.busy) return;
    if (!res || !res.ok) showError((res && res.message) || '応答がありません', res && res.field);
}

async function leave() {
    if (state.sending) return;
    setSending(true);
    const res = await post('leave', {});
    setSending(false);
    if (res && res.busy) return;
    if (!res || !res.ok) showError((res && res.message) || '応答がありません');
}

$('formCard').addEventListener('submit', (e) => {
    e.preventDefault();
    submit();
});
$('leaveBtn').addEventListener('click', leave);
$('nameInput').addEventListener('input', () => { updateCount(); showError(null); });
$('channelInput').addEventListener('input', () => showError(null));

window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !$('form').hidden) {
        e.preventDefault();
        post('close', {});
    }
});

// ================== Lua からの指示 ==================

window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.scale != null) setScale(d.scale);
    switch (d.action) {
        case 'openForm': return openForm(d);
        case 'closeForm': return closeForm();
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
            closeForm();
            onList({ channel: data.channel, members: [{ id: 12, name: data.name, down: false }, ...Sample.members.slice(1)], self: 12 });
            return { ok: true, channel: data.channel };
        }
        if (name === 'leave') { closeForm(); onLeft(); return { ok: true }; }
        if (name === 'close') { closeForm(); return {}; }
        return null;
    },
    run(scene) {
        document.body.classList.add('sample');
        setScale(1);
        const list = (members) => onList({ channel: '102.5', members, self: 12, maxRows: 12 });
        const many = Array.from({ length: 16 }, (_, i) => ({ id: 40 + i, name: `隊員 ${i + 1}`, down: i === 5 }));
        const scenes = {
            list: () => { list(Sample.members); onTalk({ id: 4, on: true }); },
            self: () => { list(Sample.members); onTalk({ id: 12, on: true }); },
            many: () => { onList({ channel: '7', members: many, self: 40, maxRows: 12 }); onTalk({ id: 42, on: true }); },
            long: () => list([{ id: 112, name: 'とても長い表示名を入れたときの人', down: false }, ...Sample.members]),
            form: () => openForm({ name: '早瀬 晴', channel: '102.5', onRadio: false, limits: { name: 16, min: 1, max: 500 } }),
            formOn: () => {
                list(Sample.members);
                openForm({ name: '早瀬 晴', channel: '102.5', onRadio: true, limits: { name: 16, min: 1, max: 500 } });
            },
            formError: () => {
                openForm({ name: '早瀬 晴', channel: '3', onRadio: false, limits: { name: 16, min: 1, max: 500 } });
                submit();
            },
            formEmpty: () => openForm({ name: '', channel: '', onRadio: false, limits: { name: 16, min: 1, max: 500 } }),
        };
        (scenes[scene] || scenes.list)();
    },
};

if (!RES && location.protocol === 'file:') Sample.run(location.hash.slice(1));
