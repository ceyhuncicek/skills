'use strict';

const { getRegistry } = require('../registry');

module.exports = function list() {
  const skills = getRegistry();
  if (skills.length === 0) {
    console.log('No bundled skills found.');
    return;
  }
  console.log('Bundled skills:\n');
  for (const skill of skills) {
    console.log(`  ${skill.name}  v${skill.version}`);
    if (skill.description) {
      const short = skill.description.length > 80
        ? skill.description.slice(0, 77) + '...'
        : skill.description;
      console.log(`    ${short}`);
    }
  }
};
