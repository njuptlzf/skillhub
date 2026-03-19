---
name: pr-to-docs
description: Generate Requirements Analysis, Design Specification, and Implementation Plan documents from Gitea PR code changes. Auto-detects language. Strictly distinguishes product perspective (requirements) from technical perspective (design).
---

# PR-to-Docs

Generate technical documents from PR code changes.

## Quick Reference

| Document Type | Perspective | Code/Pseudocode | Template |
|--------------|-------------|-----------------|----------|
| **Requirements Analysis** | Product | ❌ Forbidden | [templates/requirements-analysis.md](templates/requirements-analysis.md) |
| **Design Specification** | Technical | ✅ Required | [templates/design-specification.md](templates/design-specification.md) |
| **Implementation Plan** | Implementation | ✅ Required | [templates/implementation-plan.md](templates/implementation-plan.md) |

## Core Principles

1. **Extract intent** from code, don't just describe changes
2. **Design perspective** - no PR numbers or repo paths
3. **Auto language detection** - generates in your preferred language
4. **Document perspective rules** - see below

## Document Perspective Rules

### ⚠️ Critical Distinction

| Dimension | Requirements Analysis | Design Specification |
|-----------|---------------------|---------------------|
| Perspective | Product | Technical |
| Audience | PM, Business | Developers, Architects |
| Answers | "What & Why" | "How & With What" |
| Code/Pseudocode | ❌ Forbidden | ✅ Required |
| Architecture Diagram | ❌ Not needed | ✅ Required |

### ❌ Common Mistake

**Requirements with code (wrong):**
```markdown
## 4. Functional Requirements

func (r *DBRouter) GetTargetDB(dbKey string) {
    // ...
}
```

**Correct**: Requirements only describe business needs. Designers create design specs.

## Input Formats

```
# Single PR
Analyze #83

# Multi-PR
Based on PR #83 and #672, generate documents

# With context
Original requirements: Support custom sharding
Based on PR #672, generate documents
```

## Best Practices

1. **Auto-detect language** - no confirmation needed
2. **Modular organization** - by feature, not by PR
3. **Quality check before output** - verify document perspective
4. **Use standardized templates** - from [templates/](templates/)
5. **Use Mermaid for all diagrams** - never use ASCII art

### ⚠️ Mermaid Requirement

**All diagrams must use Mermaid, never ASCII art.**

## Additional Resources

- [Requirements Analysis Template](templates/requirements-analysis.md)
- [Design Specification Template](templates/design-specification.md)
- [Implementation Plan Template](templates/implementation-plan.md)
