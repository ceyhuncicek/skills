'use strict';

const fs = require('fs');
const path = require('path');
const { parseFrontmatter } = require('./utils');

const SKILLS_DIR = path.join(__dirname, '..', 'skills');

/**
 * Returns an array of all bundled skills with their metadata.
 * Each entry: { name, description, version, skillFile }
 */
function getRegistry() {
  const entries = fs.readdirSync(SKILLS_DIR, { withFileTypes: true });
  const skills = [];

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const skillFile = path.join(SKILLS_DIR, entry.name, 'SKILL.md');
    if (!fs.existsSync(skillFile)) continue;

    const content = fs.readFileSync(skillFile, 'utf8');
    const meta = parseFrontmatter(content);
    skills.push({
      name: entry.name,
      description: meta.description || '',
      version: (meta.metadata && meta.metadata.version) || '0.0.0',
      skillFile,
    });
  }

  return skills;
}

/**
 * Returns a single skill from the registry by name, or null if not found.
 */
function getSkill(name) {
  return getRegistry().find((s) => s.name === name) || null;
}

module.exports = { getRegistry, getSkill };
