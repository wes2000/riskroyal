const crypto = require('node:crypto');

const ALPHABET = '23456789ABCDEFGHJKMNPQRSTVWXYZ';

function generateCode() {
  const bytes = crypto.randomBytes(6);
  let out = '';
  for (let i = 0; i < 6; i++) {
    out += ALPHABET[bytes[i] % ALPHABET.length];
  }
  return out;
}

function normalizeCode(input) {
  if (typeof input !== 'string') return null;
  return input.trim().toUpperCase();
}

module.exports = { generateCode, normalizeCode, ALPHABET };
