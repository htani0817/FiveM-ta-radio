// Lua の構文と、未定義のグローバル参照を調べる（ta-dealer の check.js と同じ方法）
// node check.js <リソースのフォルダ>
const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');
const dir = process.argv[2];
const files = ['fxmanifest.lua', 'config.lua', 'server/main.lua', 'client/main.lua'];
const known = new Set((
  // このリソースのグローバル
  'Config ' +
  // ox_lib・qbx_core・oxmysql・FiveM の Lua
  'lib cache exports json source MySQL Player LocalPlayer utf8 ' +
  'print pairs ipairs type tostring tonumber math table string next select error pcall ' +
  'CreateThread Wait SetTimeout GetGameTimer TriggerClientEvent TriggerServerEvent AddEventHandler RegisterNetEvent ' +
  'RegisterCommand GetCurrentResourceName AddStateBagChangeHandler GetPlayerFromStateBagName ' +
  // client の native
  'SendNUIMessage RegisterNUICallback SetNuiFocus IsPauseMenuActive IsEntityDead vec3 joaat ' +
  'TaskPlayAnim StopAnimTask CreateObject SetEntityCollision AttachEntityToEntity GetPedBoneIndex SetModelAsNoLongerNeeded ' +
  'GetEntityCoords DoesEntityExist DeleteEntity ' +
  // fxmanifest
  'fx_version game lua54 name description author version ui_page files shared_scripts client_scripts server_scripts dependencies data_file'
).split(/\s+/));
let bad = 0;
for (const f of files) {
  const src = fs.readFileSync(path.join(dir, f), 'utf8');
  if (src.charCodeAt(0) === 0xfeff) { console.log(f, 'BOM あり'); bad++; }
  if (src.includes('\r')) { console.log(f, 'CR あり'); bad++; }
  let ast;
  try {
    ast = luaparse.parse(src, { scope: true, luaVersion: '5.3' });
  } catch (e) { console.log(f, '構文エラー', e.message); bad++; continue; }
  const globals = new Set();
  (function walk(n) {
    if (!n || typeof n !== 'object') return;
    if (Array.isArray(n)) return n.forEach(walk);
    if (n.type === 'Identifier' && n.isLocal === false && !known.has(n.name)) globals.add(n.name);
    for (const k in n) if (k !== 'type') walk(n[k]);
  })(ast.body);
  if (globals.size) bad++;
  console.log(f, 'OK', globals.size ? '未知のグローバル: ' + [...globals].join(', ') : '');
}
// NUI のファイルも BOM と CR を調べる
for (const f of ['html/index.html', 'html/style.css', 'html/app.js', 'README.md']) {
  const src = fs.readFileSync(path.join(dir, f), 'utf8');
  if (src.charCodeAt(0) === 0xfeff) { console.log(f, 'BOM あり'); bad++; }
  if (src.includes('\r')) { console.log(f, 'CR あり'); bad++; }
}
process.exit(bad ? 1 : 0);
