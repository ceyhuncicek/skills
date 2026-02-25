'use strict';

const { getSkill } = require('../registry');
const { getInstalledVersion, installSkill } = require('../installer');

module.exports = function add(name) {
  if (!name) {
    console.error('Usage: skills add <skill-name>');
    process.exit(1);
  }

  const skill = getSkill(name);
  if (!skill) {
    console.error(`Skill "${name}" not found in registry.`);
    console.error('Run "skills list" to see available skills.');
    process.exit(1);
  }

  const installed = getInstalledVersion(name);
  if (installed === skill.version) {
    console.log(`"${name}" v${skill.version} is already installed.`);
    return;
  }

  installSkill(skill);

  if (installed) {
    console.log(`Updated "${name}" from v${installed} to v${skill.version}.`);
  } else {
    console.log(`Installed "${name}" v${skill.version}.`);
  }
};
