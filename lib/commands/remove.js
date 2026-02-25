'use strict';

const path = require('path');
const fs = require('fs');
const { getSkillsDir } = require('../utils');
const { removeSkill } = require('../installer');

module.exports = function remove(name) {
  if (!name) {
    console.error('Usage: skills remove <skill-name>');
    process.exit(1);
  }

  const dest = path.join(getSkillsDir(), name);
  if (!fs.existsSync(dest)) {
    console.error(`"${name}" is not installed.`);
    process.exit(1);
  }

  removeSkill(name);
  console.log(`Removed "${name}".`);
};
