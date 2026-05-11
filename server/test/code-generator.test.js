const { test } = require('node:test');
const assert = require('node:assert/strict');
const { generateCode, normalizeCode, ALPHABET } = require('../src/code-generator');

test('ALPHABET excludes ambiguous chars and has 30 unique letters', () => {
  assert.equal(ALPHABET.length, 30);
  assert.equal(new Set(ALPHABET).size, 30);
  for (const bad of ['0', 'O', '1', 'I', 'L', 'U']) {
    assert.ok(!ALPHABET.includes(bad), `ALPHABET must not include "${bad}"`);
  }
});

test('generateCode returns 6 uppercase chars from ALPHABET', () => {
  for (let i = 0; i < 50; i++) {
    const c = generateCode();
    assert.equal(c.length, 6, `got "${c}"`);
    assert.equal(c, c.toUpperCase(), `got "${c}"`);
    for (const ch of c) {
      assert.ok(ALPHABET.includes(ch), `char "${ch}" not in ALPHABET (code="${c}")`);
    }
  }
});

test('generateCode produces few collisions across 10000 samples', () => {
  const codes = new Set();
  for (let i = 0; i < 10000; i++) codes.add(generateCode());
  // 30^6 = ~729M codepoints. Expected collisions in 10k samples << 1.
  assert.ok(codes.size > 9990, `only ${codes.size} unique out of 10000`);
});

test('normalizeCode uppercases and trims', () => {
  assert.equal(normalizeCode('  abc234 '), 'ABC234');
  assert.equal(normalizeCode('AbCdEf'), 'ABCDEF');
  assert.equal(normalizeCode(''), '');
  assert.equal(normalizeCode(null), null);
  assert.equal(normalizeCode(undefined), null);
});
