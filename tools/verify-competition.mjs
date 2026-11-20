import fs from 'node:fs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { competitionRuleErrors, competitionEvidenceErrors, REQUIRED_MARKET_CHECKS } from './competition-policy.mjs';

const rules = JSON.parse(fs.readFileSync(new URL('../release/competition.json', import.meta.url), 'utf8'));
const now = Date.parse('2026-10-31T12:00:00+08:00');
const expected = { bundleName: 'com.retempt.flowmind', versionName: '1.1.0', versionCode: 1010000,
  sourceCommit: 'a'.repeat(40), appSha256: 'b'.repeat(64) };
const report = () => ({ mode: 'submission', marketReady: true, ...expected,
  generatedAt: '2026-10-31T10:00:00+08:00', checks: REQUIRED_MARKET_CHECKS.map(id => ({ id, status: 'PASS' })) });
const evidence = () => ({ schemaVersion: 1, stage: 'preliminary', ...expected, channel: 'appgallery_public_preview',
  status: 'published', publicAccessible: true, requiresInvitation: false, marketUrl: 'https://appgallery.huawei.com/app/test-fixture',
  publishedAt: '2026-10-30T09:00:00+08:00', reviewed: true, reviewer: 'policy test fixture', checkedAt: '2026-10-31T11:00:00+08:00',
  marketProof: 'release/evidence/fixture-status.png', downloadProof: 'release/evidence/fixture-download.png' });
const errors = (e, r = report(), stage = 'preliminary', clock = now) => competitionEvidenceErrors(rules, stage, e, expected, r, clock);

test('configured scoring and stage rules preserve the supplied competition requirements', () => assert.deepEqual(competitionRuleErrors(rules), []));
test('preliminary accepts public preview and formal market evidence', () => {
  assert.deepEqual(errors(evidence()), []);
  assert.deepEqual(errors({ ...evidence(), channel: 'appgallery_formal' }), []);
});
for (const channel of ['apptest_invitation', 'invitation_test', 'github_release', 'local_package', 'unknown']) {
  test(`competition blocks nonqualifying channel ${channel}`, () => assert.ok(errors({ ...evidence(), channel }).length));
}
for (const [label, change] of [
  ['review pending', { status: 'in_review' }], ['requires invitation', { requiresInvitation: true }],
  ['not public', { publicAccessible: false }], ['missing reviewer', { reviewer: '' }], ['not reviewed', { reviewed: false }],
  ['old version', { versionCode: 1001005 }], ['different bundle', { bundleName: 'com.other.app' }],
  ['old source', { sourceCommit: 'c'.repeat(40) }], ['different APP', { appSha256: 'd'.repeat(64) }],
  ['future publication', { publishedAt: '2026-11-01T01:00:00+08:00' }],
  ['timestamp without timezone', { publishedAt: '2026-10-30T09:00:00' }],
  ['nonexistent calendar day', { publishedAt: '2026-02-31T09:00:00+08:00' }],
  ['stale review', { checkedAt: '2026-10-01T00:00:00+08:00' }], ['future review', { checkedAt: '2026-11-01T00:00:00+08:00' }],
  ['review before publication', { checkedAt: '2026-10-29T00:00:00+08:00' }],
  ['missing download proof', { downloadProof: '' }], ['unofficial link', { marketUrl: 'https://example.com/app' }],
  ['HTTP link', { marketUrl: 'http://appgallery.huawei.com/app/test' }]
]) test(`competition blocks ${label}`, () => assert.ok(errors({ ...evidence(), ...change }).length));
test('project-only, stale, blocked and mismatched market preflight reports cannot qualify', () => {
  for (const change of [{ mode: 'project-only' }, { marketReady: false }, { checks: [] },
    { checks: [{ status: 'BLOCKED' }] }, { checks: [{ id: 'package_signature', status: 'PASS' }] },
    { checks: [null] }, { appSha256: 'c'.repeat(64) }, { generatedAt: '2026-10-01T00:00:00Z' }]) {
    assert.ok(errors(evidence(), { ...report(), ...change }).length);
  }
});
test('preliminary deadline is inclusive and evaluated in Shanghai time', () => {
  const clock = Date.parse('2026-11-01T00:30:00+08:00');
  assert.deepEqual(errors({ ...evidence(), publishedAt: '2026-10-31T15:59:59Z', checkedAt: '2026-11-01T00:10:00+08:00' }, report(), 'preliminary', clock), []);
  assert.ok(errors({ ...evidence(), publishedAt: '2026-10-31T16:00:00Z', checkedAt: '2026-11-01T00:10:00+08:00' }, report(), 'preliminary', clock).length);
});
test('final accepts only formal market publication before November 27 in Shanghai', () => {
  const clock = Date.parse('2026-11-27T01:00:00+08:00');
  const r = { ...report(), generatedAt: '2026-11-26T10:00:00+08:00' };
  const e = { ...evidence(), stage: 'final', channel: 'appgallery_formal', publishedAt: '2026-11-26T15:59:59Z', checkedAt: '2026-11-27T00:30:00+08:00' };
  assert.deepEqual(errors(e, r, 'final', clock), []);
  assert.ok(errors({ ...e, channel: 'appgallery_public_preview' }, r, 'final', clock).length);
  assert.ok(errors({ ...e, publishedAt: '2026-11-26T16:00:00Z' }, r, 'final', clock).length);
});
test('missing evidence and invalid stages stay blocked', () => {
  assert.ok(errors(null).length);
  assert.ok(errors(evidence(), report(), 'unknown').length);
});
test('invalid rule documents fail closed without evaluating evidence', () => {
  for (const invalid of [null, {}, { ...rules, scoring: { ...rules.scoring, innovation: 40 } },
    { ...rules, stages: { ...rules.stages, final: { ...rules.stages.final, allowedChannels: ['appgallery_public_preview'] } } }]) {
    assert.ok(competitionEvidenceErrors(invalid, 'preliminary', evidence(), expected, report(), now).length);
  }
});
