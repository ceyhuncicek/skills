# @ceyhuncicek/skills

CLI to install and manage personal Claude Code skills.

## Install

```bash
npm install -g @ceyhuncicek/skills
# or use directly with npx (no install needed):
npx @ceyhuncicek/skills <command>
```

## Commands

```bash
skills list                 # Show all bundled skills and versions
skills add <name>           # Install a skill to ~/.claude/skills/
skills remove <name>        # Remove an installed skill
skills update <name>        # Update an installed skill to latest version
skills installed            # Show installed skills and update status
```

## Available Skills

| Skill | Description |
|-------|-------------|
| `pipeline` | Multi-agent dev pipeline (PM → parallel Coders → Reviewer) |
| `deep-pipeline` | Deep research pipeline with dual-PM planning and research agents |
| `story-writer` | Write short stories with professional craft and structure |
| `text-fixer` | Fix text to be natural, clear, and human-sounding |

## Usage Examples

```bash
# See what's available
npx @ceyhuncicek/skills list

# Install a skill
npx @ceyhuncicek/skills add pipeline

# Check installed skills for updates
npx @ceyhuncicek/skills installed

# Update a skill to latest version
npx @ceyhuncicek/skills update pipeline

# Remove a skill
npx @ceyhuncicek/skills remove pipeline
```

## Publishing a New Version

To release updated skill content:

1. Edit `skills/<name>/SKILL.md` and bump `version:` in the frontmatter
2. Run:

```bash
npm version patch
npm publish --access public
```

Users get the update by running:

```bash
npx @ceyhuncicek/skills update <name>
```

## Development

```bash
# Test locally without installing
node bin/skills.js list
node bin/skills.js add pipeline
node bin/skills.js installed
node bin/skills.js remove pipeline
```

## First-Time Publish

```bash
npm login
npm publish --access public
```
