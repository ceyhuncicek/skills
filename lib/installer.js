'use strict';

const fs = require('fs');
const path = require('path');
const { getSkillsDir, parseFrontmatter } = require('./utils');

/**
 * Returns the installed version of a skill, or null if not installed.
 */
function getInstalledVersion(name) {
  const skillFile = path.join(getSkillsDir(), name, 'SKILL.md');
  if (!fs.existsSync(skillFile)) return null;
  const content = fs.readFileSync(skillFile, 'utf8');
  const meta = parseFrontmatter(content);
  return meta.version || null;
}

/**
 * Copies a skill directory from the bundle into ~/.claude/skills/<name>/.
 * Creates the destination directory if needed.
 */
function installSkill(skill) {
  const dest = path.join(getSkillsDir(), skill.name);
  fs.mkdirSync(dest, { recursive: true });
  fs.copyFileSync(skill.skillFile, path.join(dest, 'SKILL.md'));
}

/**
 * Removes a skill directory from ~/.claude/skills/<name>/.
 */
function removeSkill(name) {
  const dest = path.join(getSkillsDir(), name);
  fs.rmSync(dest, { recursive: true, force: true });
}

module.exports = { getInstalledVersion, installSkill, removeSkill };
