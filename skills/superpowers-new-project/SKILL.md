---
name: superpowers:new-project
description: Superpowers workflow for starting new projects - integrates GSD + gstack workflows into superpowers lifecycle
---

# New Project Superpowers Workflow

**Announce at start:** "I'm using the superpowers:new-project skill to initiate a new project with GSD+gstack integration."

## Context Requirements

This skill assumes you have:
1. GSD installed (`npx get-shit-done-cc --claude --global`)
2. gstack installed (in `.claude/skills/gstack` with `./setup` run)
3. CLAUDE.md configured with GSD+gstack workflow

## Overview

This skill guides you through the **complete new project launch workflow** that integrates:
- **superpowers** methodology
- **GSD** project planning and execution framework
- **gstack** quality gates and role-based reviews

**Important:** This skill should be run BEFORE any creative work or brainstorming. It sets up the project foundation that all subsequent superpowers skills will build upon.

## Workflow Steps

### Step 0: Pre-flight Check
Before starting, ensure you're in an empty directory or the target project location.

### Step 1: CEO Vision Alignment (`/office-hours` - gstack)
**REQUIRED SUB-SKILL:** Use gstack skills via Skill tool

```bash
Skill tool: "/office-hours"
```

**What happens:**
- gstack CEO mode asks 6 forcing questions
- Forces you to articulate: user problem, differentiation, success metrics in your own words
- Creates shared understanding of WHAT we're building and WHY

**Output:** Clear product positioning that feeds into GSD planning

### Step 2: Project Initialization (`/gsd:new-project` - GSD)
**REQUIRED SUB-SKILL:** Use GSD command

```bash
Skill tool: "/gsd:new-project"
```

**Provide context:** Share the `/office-hours` conclusions as input

**What happens:**
- GSD extracts requirements from the vision
- Generates `.planning/PROJECT.md` with vision, target users, success criteria
- Creates `.planning/ROADMAP.md` with phased implementation plan
- Sets up `.planning/` directory structure for GSD workflow

**Output:** Formal project definition and phased roadmap

### Step 3: Architecture Review (`/plan-eng-review` - gstack)
**REQUIRED SUB-SKILL:** Use gstack skills via Skill tool

```bash
Skill tool: "/plan-eng-review"
```

**What happens:**
- Engineering manager review of technical architecture
- Locks down: tech stack choices, data flow, system boundaries
- Documents decisions in `DESIGN.md`
- Prevents later architectural drift

**Output:** Approved technical architecture

### Step 4: Phase 1 Discussion (`/gsd:discuss-phase 1` - GSD)
**REQUIRED SUB-SKILL:** Use GSD command

```bash
Skill tool: "/gsd:discuss-phase 1"
```

**What happens:**
- Confirms design decisions for Phase 1
- Captures preferences and constraints
- Generates `.planning/phases/1-*/DISCUSSION-LOG.md`
- Ensures alignment before deep planning

**Output:** Approved Phase 1 scope and approach

### Step 5: Design Review (if UI involved) (`/plan-design-review` - gstack)
**Conditional:** Only if Phase 1 involves UI work

```bash
Skill tool: "/plan-design-review"
```

**What happens:**
- Design review across interaction, visual, information architecture dimensions
- Scores 0-10 on each design dimension
- Identifies design gaps before implementation
- Generates design requirements

### Step 6: UI Contract Lock (if UI involved) (`/gsd:ui-phase 1` - GSD)
**Conditional:** Only if Phase 1 involves UI work

```bash
Skill tool: "/gsd:ui-phase 1"
```

**What happens:**
- Freezes design contract (spacing/typography/colors/copy guidelines)
- Creates `.planning/phases/1-*/UI-SPEC.md`
- Prevents component inconsistency

## Integration with Other Superpowers Skills

This skill sets up the foundation for subsequent superpowers workflows:

### After This Skill, Continue With:
1. **Deep Planning:** `/gsd:plan-phase 1` or `superpowers:writing-plans`
2. **Implementation:** `/gsd:execute-phase 1` or `superpowers:subagent-driven-development`
3. **Quality Gates:** `superpowers:verification-before-completion`
4. **Code Review:** `superpowers:requesting-code-review`
5. **Shipping:** `superpowers:finishing-a-development-branch`

## File Structure Created

```
.planning/
├── PROJECT.md          # Vision, target users, success criteria
├── REQUIREMENTS.md     # Feature requirements
├── CONTEXT.md          # Technical constraints
├── ROADMAP.md          # Phase-by-phase implementation plan
├── STATE.md            # Session state (crash recovery)
└── phases/
    └── 1-{slug}/
        ├── DISCUSSION-LOG.md  # Phase 1 decisions
        └── UI-SPEC.md        # UI design contract (if applicable)
```

## Skill Dependencies

**Required Tools:**
- GSD: For project planning and execution framework
- gstack: For quality gates and role-based reviews
- superpowers: For consistent development methodology

**Required Skills:**
- `superpowers:using-superpowers` (prerequisite)
- `gstack` skills (via Skill tool)
- `gsd:*` commands (via Skill tool)

## Verification Checklist

Before claiming completion, verify:

- [ ] `/office-hours` completed with clear product positioning
- [ ] `/gsd:new-project` generated `.planning/` directory with PROJECT.md and ROADMAP.md
- [ ] `/plan-eng-review` approved technical architecture
- [ ] `/gsd:discuss-phase 1` captured Phase 1 decisions
- [ ] Appropriate design reviews completed (if UI involved)
- [ ] Project is ready for deep planning (Phase 1)

## Common Issues & Resolutions

**Issue:** gstack skills not working
**Resolution:** Run `cd .claude/skills/gstack && ./setup`

**Issue:** GSD not installed
**Resolution:** Run `npx get-shit-done-cc --claude --global`

**Issue:** Skills not appearing in list
**Resolution:** Check `.claude/skills/` directory and symlinks

**Issue:** Office-hours questions unclear
**Resolution:** Re-run, provide detailed answers about user problem, differentiation, success metrics

## Success Criteria

The new project setup is complete when:
1. Project has clear vision and success criteria (PROJECT.md)
2. Implementation is broken into manageable phases (ROADMAP.md)
3. Technical architecture is approved (engineering review)
4. Phase 1 scope and approach are confirmed (DISCUSSION-LOG.md)
5. UI design contract is locked (if applicable, UI-SPEC.md)
6. Team is ready to proceed with deep planning for Phase 1

---

*This skill integrates GSD (github.com/gsd-build/get-shit-done) + gstack (github.com/garrytan/gstack) + superpowers workflows.*
*Follows CLAUDE.md global configuration for AI development workflows.*
