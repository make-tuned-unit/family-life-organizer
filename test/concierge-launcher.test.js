// Guards the Home ✨ launcher's touch-and-hold → listening behaviour.
// Regression: a consent guard in the gesture's onChanged silently dropped every
// hold once AI consent keys were reset, so long-press did nothing.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.join(__dirname, '..');
const read = rel => fs.readFileSync(path.join(root, rel), 'utf8');
const swiftc = spawnSync('xcrun', ['--find', 'swiftc'], { encoding: 'utf8' }).status === 0;

test('launcher press policy: taps open, holds always reach listening', { skip: !swiftc && 'swiftc unavailable' }, () => {
  const out = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'kinrows-launcher-')), 'check');
  const build = spawnSync('xcrun', ['swiftc', '-parse-as-library',
    'FamilyLife/Views/Concierge/ConciergeLauncherPress.swift', 'test/concierge-launcher-press.swift', '-o', out],
    { cwd: root, encoding: 'utf8' });
  assert.equal(build.status, 0, build.stderr);
  const run = spawnSync(out, { encoding: 'utf8' });
  assert.equal(run.status, 0, run.stdout + run.stderr);
  assert.match(run.stdout, /ok/);
});

test('launcher button delegates every press outcome to the policy', () => {
  const src = read('FamilyLife/Views/Concierge/AskButlerButton.swift');
  const button = src.slice(src.indexOf('struct ConciergeLauncherButton'), src.indexOf('struct PushToTalkOverlay'));
  assert.ok(button.length > 0, 'ConciergeLauncherButton exists');
  // The press must never be dropped on consent before it is tracked.
  assert.doesNotMatch(button, /guard\s+AIConsentManager\.hasConciergeConsent\s+else\s*\{\s*return\s*\}/,
    'consent must not early-return out of the press gesture');
  assert.match(button, /press\.pressBegan\(hasConsent:/);
  assert.match(button, /press\.holdElapsed\(pressID:/);
  assert.match(button, /case \.beginPushToTalk:\s*\n\s*ptt\.begin\(\)/);
  assert.match(button, /case \.endPushToTalk: ptt\.end\(api: api\)/);
  assert.match(button, /case \.listenAfterConsent: onListen\(\)/);
  assert.match(button, /case \.open: onOpen\(\)/);
});

test('Home wires the launcher hold to the Concierge listen flow', () => {
  const content = read('FamilyLife/App/ContentView.swift');
  assert.match(content, /ConciergeLauncherButton\(ptt: ptt\)[\s\S]{0,300}onListen:[\s\S]{0,200}conciergeLaunch\.listen\(\)/);
  const view = read('FamilyLife/Views/Concierge/ConciergeView.swift');
  assert.match(view, /chatAutoListen = request\.autoListen/, 'ConciergeView forwards autoListen to the chat');
  assert.match(view, /ConciergeChatView\(initialPrompt: chatPrompt, autoListen: chatAutoListen/);
  const chat = read('FamilyLife/Views/Concierge/ConciergeChatView.swift');
  assert.match(chat, /guard autoListen, !didAutoListen/, 'chat starts dictation on an autoListen launch');
});

test('launcher policy is compiled into the app target', () => {
  const pbx = read('FamilyLife.xcodeproj/project.pbxproj');
  assert.match(pbx, /ConciergeLauncherPress\.swift in Sources \*\/ = \{isa = PBXBuildFile/);
  assert.match(pbx, /[A-F0-9]{8} \/\* ConciergeLauncherPress\.swift in Sources \*\/,/);
});
