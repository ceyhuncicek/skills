'use strict';

const fs = require('fs');
const path = require('path');
const { getSkillsDir } = require('../utils');
const { getRegistry } = require('../registry');
const { getInstalledVersion } = require('../installer');

module.exports = function installed() {
  const skillsDir = getSkillsDir();

  if (!fs.existsSync(skillsDir)) {
    console.log('No skills directory found at ~/.claude/skills/');
    return;
  }

  const entries = fs.readdirSync(skillsDir, { withFileTypes: true })
    .filter((e) => e.isDirectory());

  if (entries.length === 0) {
    console.log('No skills installed.');
    return;
  }

  const registry = getRegistry();
  const registryMap = new Map(registry.map((s) => [s.name, s]));

  console.log('Installed skills:\n');
  for (const entry of entries) {
    const name = entry.name;
    const installedVersion = getInstalledVersion(name);
    const bundled = registryMap.get(name);

    let status = '';
    if (!bundled) {
      status = '(not in registry)';
    } else if (!installedVersion) {
      status = '(no version info)';
    } else if (installedVersion === bundled.version) {
      status = 'up to date';
    } else {
      status = `update available: v${installedVersion} → v${bundled.version}`;
    }

    const versionStr = installedVersion ? `v${installedVersion}` : '(unknown)';
    console.log(`  ${name}  ${versionStr}  ${status}`);
  }
};
