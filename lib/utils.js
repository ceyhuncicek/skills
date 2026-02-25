'use strict';

const os = require('os');
const path = require('path');

/**
 * Returns the path to the user's ~/.claude/skills directory.
 */
function getSkillsDir() {
  return path.join(os.homedir(), '.claude', 'skills');
}

/**
 * Parses YAML-style frontmatter from a markdown string.
 * Returns an object with the parsed key-value pairs.
 * Handles simple string values and one level of nested objects.
 */
function parseFrontmatter(content) {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  if (!match) return {};

  const result = {};
  let currentKey = null;
  for (const line of match[1].split('\n')) {
    if (!line.trim()) continue;
    const isIndented = line.match(/^\s+\S/);
    if (isIndented && currentKey) {
      const colon = line.indexOf(':');
      if (colon === -1) continue;
      const key = line.slice(0, colon).trim();
      const value = line.slice(colon + 1).trim().replace(/^["']|["']$/g, '');
      if (key) {
        if (typeof result[currentKey] !== 'object') result[currentKey] = {};
        result[currentKey][key] = value;
      }
    } else {
      const colon = line.indexOf(':');
      if (colon === -1) continue;
      const key = line.slice(0, colon).trim();
      const value = line.slice(colon + 1).trim();
      if (key) {
        result[key] = value;
        currentKey = value === '' ? key : null;
      }
    }
  }
  return result;
}

module.exports = { getSkillsDir, parseFrontmatter };
