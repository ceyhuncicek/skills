#!/usr/bin/env node
'use strict';

const [, , command, ...args] = process.argv;

const commands = {
  list: require('../lib/commands/list'),
  add: require('../lib/commands/add'),
  remove: require('../lib/commands/remove'),
  update: require('../lib/commands/update'),
  installed: require('../lib/commands/installed'),
};

if (!command || command === '--help' || command === '-h') {
  console.log(`
@ceyhuncicek/skills — Claude Code skill manager

Usage:
  skills list                 List all bundled skills
  skills add <name>           Install a skill to ~/.claude/skills/
  skills remove <name>        Remove an installed skill
  skills update <name>        Update an installed skill to latest version
  skills installed            Show installed skills and update status
`);
  process.exit(0);
}

if (!commands[command]) {
  console.error(`Unknown command: "${command}"`);
  console.error('Run "skills --help" for usage.');
  process.exit(1);
}

commands[command](...args);
