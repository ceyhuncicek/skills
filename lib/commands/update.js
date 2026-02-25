'use strict';

const path = require('path');
const fs = require('fs');
const { getSkillsDir } = require('../utils');
const { getSkill } = require('../registry');
const { getInstalledVersion, installSkill } = require('../installer');

module.exports = function update(name) {
  if (!name) {
    console.error('Usage: skills update <skill-name>');
    process.exit(1);
  }

  const dest = path.join(getSkillsDir(), name);
  if (!fs.existsSync(dest)) {
    console.error(`"${name}" is not installed. Run "skills add ${name}" first.`);
    process.exit(1);
  }

  const skill = getSkill(name);
  if (!skill) {
    console.error(`"${name}" is not in the registry.`);
    console.error('The bundled package may not include this skill. Try updating the package:');
    console.error('  npm install -g @ceyhuncicek/skills@latest');
    process.exit(1);
  }

  const installed = getInstalledVersion(name);
  if (installed === skill.version) {
    console.log(`"${name}" is already up to date (v${skill.version}).`);
    return;
  }

  installSkill(skill);
  console.log(`Updated "${name}" from v${installed} to v${skill.version}.`);
};
