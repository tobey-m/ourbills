import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const read=path=>readFileSync(new URL('../'+path,import.meta.url),'utf8');
// Compile every inline entry script, including the retained guest app.
for(const file of ['index.html','split.html','shared.html']){
 const html=read(file);
 for(const [,attrs,script] of html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)){
  if(!attrs.includes('type="module"'))new vm.Script(script,{filename:file});
 }
}
const landing=read('index.html'),guest=read('split.html');
assert.match(landing,/href="\/split"/);assert.match(landing,/href="\/shared"/);
assert.match(guest,/KEY='ourbills_v2_data'/);
assert.match(guest,/INBOX_DB='ourbills_receipts_v3'/);
assert.ok(!landing.includes('localStorage.setItem'));
assert.ok(!landing.includes('indexedDB.deleteDatabase'));
const app=read('shared.js');
assert.match(app,/storageKey:'ourbills_cloud_auth_v1',persistSession:true,autoRefreshToken:true/);
assert.match(app,/mode:'couple'/);
assert.match(app,/id="receiptFile"[^>]*hidden/);
console.log('PASS: page scripts parse; guest storage identities and auth storage retained; entry routes present; receipt picker uses custom control.');
