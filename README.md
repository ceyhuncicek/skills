# cey — Claude Code plugin marketplace

A personal [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces) that
distributes one plugin, `cey-skills`, containing my working set of skills.

Installing the plugin makes every skill below available in Claude Code automatically — no copying files
into `~/.claude/skills/` and no CLI to keep in sync.

## Register the marketplace

```bash
claude plugin marketplace add ceyhuncicek/skills
```

Or from inside a Claude Code session:

```
/plugin marketplace add ceyhuncicek/skills
```

## Install the plugin

```bash
claude plugin install cey-skills@cey
```

Or in-session:

```
/plugin install cey-skills@cey
```

Restart Claude Code to load the skills.

## Update

```bash
claude plugin marketplace update cey
claude plugin update cey-skills
```

The first command refreshes the catalog, the second pulls the new plugin version. Restart to apply.

## Skills

| Skill | What it does |
|-------|--------------|
| `agent-pipeline` | Multi-agent dev pipeline: PM plans and groups subtasks by file ownership, parallel Coders implement, Reviewer checks. |
| `brainstorming` | Explores intent, approaches, and design decisions before any implementation or planning starts. |
| `deep-pipeline` | Deeper pipeline: dedicated research agents, then dual-PM Actor-Critic planning, then parallel Coders and a Reviewer. |
| `document-review` | Refines a brainstorm or plan document before moving to the next step of the workflow. |
| `fable-gpt` | Fable orchestrates and reviews while Codex implements. |
| `fable-opus` | Fable plans, directs, and reviews while Opus agents research and implement in a worktree. |
| `frontend-design` | Builds distinctive, production-grade frontend interfaces that avoid generic AI aesthetics. |
| `git-worktree` | Creates, lists, switches, and cleans up Git worktrees for parallel development. |
| `humanizer` | Strips the tells of AI-generated prose, based on Wikipedia's "Signs of AI writing" guide. |
| `img2threejs` | Turns a reference image into a quality-gated, animation-ready procedural Three.js model. |
| `story-writer` | Writes short fiction with real structure, curiosity hooks, and tension. |
| `text-fixer` | Rewrites text to be natural, direct, and clear: cuts clichés, fluff, and stray dashes. |

`agent-pipeline` and `deep-pipeline` need `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in your `settings.json`.

## Layout

```
.claude-plugin/marketplace.json     # the catalog
plugins/cey-skills/
  .claude-plugin/plugin.json        # plugin manifest
  skills/<name>/SKILL.md            # one directory per skill
```

## Developing

Point Claude Code at a local checkout instead of GitHub:

```bash
claude plugin marketplace add /path/to/skills
claude plugin install cey-skills@cey
```

Validate the manifests and skill files before pushing:

```bash
claude plugin validate .
claude plugin validate ./plugins/cey-skills
```

To release, edit the skill files, bump `version` in `plugins/cey-skills/.claude-plugin/plugin.json`,
and push. Users only see an update when that version string changes.

## Third-party skills

`humanizer` and `img2threejs` are vendored from their upstream projects and keep their original MIT
`LICENSE` files. `frontend-design` carries its own license terms.
