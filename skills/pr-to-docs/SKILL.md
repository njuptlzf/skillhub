---
name: pr-to-docs
description: Generate Requirements Analysis, Design Specification, and Implementation Plan documents from Gitea PR code changes. Supports cross-project multi-PR input. Auto-detects user's language preference.
type: skill
---

# PR-to-Docs Skill

## Overview

Reverse-engineer and generate technical documents from Gitea PR code changes:
- **Requirements Analysis** - What to do and why
- **Design Specification** - How to do it, architecture design, core algorithms
- **Implementation Plan** - Implementation steps, checklist

**Core Principles**:
- Describe from a **design perspective**, not "which PR this change belongs to"
- **Extract intent** from code changes, rather than describing changes themselves
- Documents are **decoupled** from specific PR numbers
- **Auto language detection** - Generate documents in user's preferred language

## Trigger Conditions

This skill activates when:
- User requests "reverse-engineer documents from PR"
- User requests "generate requirements analysis, design, implementation plan"
- User mentions "PR reverse-engineering", "code changes to documents"
- User mentions "技术文档", "需求文档" (Chinese) or "technical documents", "requirements documents" (English)

## Language Detection

### Auto-Detection Rules

The skill automatically detects user's language from:

| Signal | Chinese (`zh`) | English (`en`) |
|--------|----------------|----------------|
| System locale | `zh_CN`, `zh_TW`, `zh_HK` | `en_US`, `en_GB` |
| User message keywords | "文档", "需求", "设计", "实施" | "document", "requirements", "design", "implementation" |
| Conversation context | 中文回复倾向 | English reply tendency |

### Language Templates

#### Chinese Template Labels
| English | Chinese |
|---------|---------|
| Requirements Analysis | 需求分析 |
| Design Specification | 设计方案 |
| Implementation Plan | 实施计划 |
| Background and Status Quo | 背景与现状 |
| Core Pain Points | 核心痛点 |
| Functional Requirements | 功能需求 |
| Acceptance Criteria | 验收标准 |
| Architecture Design | 架构设计 |
| Component Responsibilities | 组件职责 |
| Key Design Decisions | 关键设计决策 |
| Implementation Steps | 实施步骤 |
| Verification Plan | 验证方案 |
| Implementation Checklist | 实施检查清单 |

## Input Format

### 1. Single PR Input
```
# English
Analyze #83 and generate documents

# 中文
查看 #83，反推生成文档
```

### 2. Multi-PR Input (Cross-Project)
```
# English
Based on PR #83 (packages) and PR #672 (kapp), generate documents

# 中文
根据 PR #83 (packages) 和 PR #672 (kapp)，反推生成文档
```

### 3. With Original Requirements Input
```
# English
Original requirements: Support custom sharding
Based on PR #83, #672, generate documents

# 中文
原始需求：支持自定义分库
根据 PR #83, #672 反推生成文档
```

### 4. Explicit Language Override
```
# English
Generate documents in English for PR #83

# 中文
请用中文为 PR #83 生成文档
```

## Implementation Flow

### Step 1: Parse Input and Detect Language

```bash
# 1. Detect user's language preference
detect_language() {
  local message="$1"
  
  # Check system locale
  if [[ "$LANG" =~ ^zh || "$LC_ALL" =~ ^zh ]]; then
    echo "zh"
    return
  fi
  
  # Check message content for Chinese characters
  if echo "$message" | grep -qE '[^\x00-\x7F]'; then
    echo "zh"
    return
  fi
  
  # Default to English
  echo "en"
}

# 2. Parse PR list
# Supported formats:
# - Single PR: #83, PR #83, Analyze #83, 查看 #83
# - Multi PR: #83, #672 or #83 (packages), #672 (kapp)

# 3. Fetch diff for each PR
for pr in "${pr_list[@]}"; do
  curl -s "${GITEA_URL}/api/v1/repos/${repo}/pulls/${pr}"
  curl -s "${GITEA_URL}/${repo}/pulls/${pr}.diff"
done
```

### Step 2: Analyze Code Changes

For each PR, perform the following analysis:

```
1. File Change Statistics
   - List of added/modified/deleted files
   - Group by module (backend/frontend/Helm/config, etc.)

2. Key Change Extraction
   - New files → New feature points
   - Modified files → Feature modification points
   - Deleted files → Removed feature points

3. Pattern Recognition
   - Data structure changes → Configuration/model design
   - Business logic changes → Core algorithms/processes
   - Template/config changes → New configuration items
```

### Step 3: Notify Language Detection (No Confirmation)

```bash
# Auto-detected language - directly generate, no confirmation needed
if [ "$LANG_CODE" = "zh" ]; then
  echo "✅ 已获取 PR 变更信息"
  echo ""
  echo "🔍 识别到的功能模块："
  echo "  - 后端核心: pkg/dbrouter/, internal/setup/migration/"
  echo "  - 配置结构: internal/setup/configs/"
  echo "  - Helm Chart: kd-cosmic-xk, kd-cosmic-migration"
  echo ""
  echo "📝 检测到中文，自动生成中文文档..."
else
  echo "✅ Fetched PR change information"
  echo ""
  echo "🔍 Identified functional modules:"
  echo "  - Backend core: pkg/dbrouter/, internal/setup/migration/"
  echo "  - Config structure: internal/setup/configs/"
  echo "  - Helm Chart: kd-cosmic-xk, kd-cosmic-migration"
  echo ""
  echo "📝 Detected English, generating English documents..."
fi

# Directly proceed to Step 4
```

### Step 4: Generate Document Structure

Based on code analysis results and detected language, generate documents:

#### Chinese Document Structure
```
# {功能名称}需求分析

## 1. 背景与现状
## 2. 核心痛点
## 3. 改造目标
## 4. 功能需求
   ### 4.1 需求点1
       - 验收条件
   ### 4.2 需求点2
       - 验收条件
## 5. 兼容性需求
## 6. 验收标准
```

```
# {功能名称}设计方案

## 1. 架构设计
   ### 1.1 整体架构图
   ### 1.2 组件职责
## 2. 核心组件设计
   ### 2.1 组件A
       - 数据结构
       - 核心方法
       - 伪代码/流程图
   ### 2.2 组件B
## 3. 配置数据结构设计
## 4. 关键设计决策
   ### 4.1 为什么这样设计？
   ### 4.2 考虑了哪些因素？
```

```
# {功能名称}实施计划

## 1. 实施范围
## 2. 实施步骤
   ### 2.1 步骤1
   ### 2.2 步骤2
## 3. 验证方案
## 4. 实施检查清单
```

#### English Document Structure
```
# {Feature Name} Requirements Analysis

## 1. Background and Status Quo
## 2. Core Pain Points
## 3. Objectives
## 4. Functional Requirements
   ### 4.1 Requirement 1
       - Acceptance Criteria
   ### 4.2 Requirement 2
       - Acceptance Criteria
## 5. Compatibility Requirements
## 6. Acceptance Criteria
```

```
# {Feature Name} Design Specification

## 1. Architecture Design
   ### 1.1 Overall Architecture Diagram
   ### 1.2 Component Responsibilities
## 2. Core Component Design
   ### 2.1 Component A
       - Data Structure
       - Core Methods
       - Pseudocode/Flowchart
   ### 2.2 Component B
## 3. Configuration Data Structure Design
## 4. Key Design Decisions
   ### 4.1 Why this design?
   ### 4.2 What factors were considered?
```

```
# {Feature Name} Implementation Plan

## 1. Scope
## 2. Implementation Steps
   ### 2.1 Step 1
   ### 2.2 Step 2
## 3. Verification Plan
## 4. Implementation Checklist
```

### Step 5: Output Summary

```bash
# Chinese output
echo "📄 已生成文档："
echo "   1. {功能名}-需求分析.md"
echo "   2. {功能名}-设计方案.md"
echo "   3. {功能名}-实施计划.md"

# English output
echo "📄 Generated documents:"
echo "   1. {Feature Name}-Requirements-Analysis.md"
echo "   2. {Feature Name}-Design-Specification.md"
echo "   3. {Feature Name}-Implementation-Plan.md"
```

## Key Principles

### 1. Design Perspective vs Implementation Perspective

| ❌ Implementation Perspective | ✅ Design Perspective |
|-------------------------------|----------------------|
| "Changes from PR #83" | "Helm Chart Configuration Rendering Design" |
| "Added DBRouter module" | "Introduced database router manager" |
| "Modified Migration struct" | "Migration component integrates routing" |

### 2. Extract Intent from Code

```go
// Code change (implementation)
type Migration struct {
    router *dbrouter.DBRouter  // New field
}

// Extract intent (design)
// Migration needs router to support dynamic DBKey -> Instance mapping
```

### 3. Language-Aware Output

| Context | Chinese | English |
|---------|---------|---------|
| Section title | "### 3.1 超级套件支持" | "### 3.1 Super Suite Support" |
| Description | "新增 DBRouter 模块" | "Introduce DBRouter module" |
| Comments | "// 新增字段" | "// New field" |

### 4. Organize by Module, Not by PR

```
├── docs/feature/{feature-name}/
│   ├── {feature-name}-requirements-analysis.md
│   ├── {feature-name}-design-specification.md
│   └── {feature-name}-implementation-plan.md
```

## Interaction Examples

### Example 1: Chinese User (Auto-Detected)

**User Input**:
```
根据 PR #83 (packages) 和 PR #672 (kapp)，反推生成文档
```

**Skill Response**:
```
✅ 已获取 2 个 PR 的代码变更

📊 变更统计：
   - PR #83: 17 个文件，+726/-467 行
   - PR #672: 34 个文件，+1407/-234 行

🔍 识别到的功能模块：
   1. DBRouter 路由管理器 - 数据库路由抽象
   2. Migration 集成 - 迁移组件支持自定义分库
   3. Helm Chart 配置 - multi_db 数组构建
   4. JsonForm Schema - 前端配置扩展

📝 检测到中文，自动生成中文文档...

📄 正在生成文档：
   - MultiDB 全自定义分库需求分析
   - MultiDB 全自定义分库设计方案
   - MultiDB 全自定义分库实施计划
```

### Example 2: English User (Auto-Detected)

**User Input**:
```
Analyze #672 and generate documents from code changes
```

**Skill Response**:
```
✅ Fetched code changes from PR #672

📊 Change Statistics: 34 files, +1407/-234 lines

🔍 Identified functional modules:
   1. DBRouter Router Manager - Database routing abstraction
   2. Migration Integration - Migration component supports custom sharding
   3. Workflow Integration - Workflow with routing capability
   4. Configuration Structure - Config struct changes

📝 Detected English, generating English documents...

📄 Generating documents:
   - MultiDB Full Custom Sharding Requirements Analysis
   - MultiDB Full Custom Sharding Design Specification
   - MultiDB Full Custom Sharding Implementation Plan
```

### Example 3: Language Override

**User Input**:
```
Generate English documents for PR #83, even though I'm using Chinese sometimes
```

**Skill Response**:
```
✅ Fetched code changes from PR #83

📝 Explicit language override: Generating in English

Ready to generate English documents for MultiDB Feature...
```

## Error Handling

### 1. PR Not Found or No Permission
```bash
if [ "$HTTP_CODE" = "404" ]; then
  echo "❌ PR not found or no access permission"
  echo "Please check PR number and repository path"
fi
```

### 2. Multi-PR Cross-Project
```bash
# Configure tokens for each repository
# GITEA_TOKEN_MAIN: Main project
# GITEA_TOKEN_PACKAGES: Packages project
```

### 3. Unable to Parse Code Changes
```bash
if [ -z "$diff_content" ]; then
  echo "❌ Unable to fetch PR diff content"
fi
```

## Output Files

Generated documents in user's language:

### Chinese Output
```
{output_dir}/
├── {功能名}-需求分析.md
├── {功能名}-设计方案.md
└── {功能名}-实施计划.md
```

### English Output
```
{output_dir}/
├── {feature-name}-requirements-analysis.md
├── {feature-name}-design-specification.md
└── {feature-name}-implementation-plan.md
```

## Best Practices

1. **Auto-detect language, no confirmation** - Detect language automatically, generate directly
2. **Understand intent first** - Infer design intent from code changes
3. **Keep documents independent** - Not dependent on specific PR numbers
4. **Modular description** - Organize by functional modules
5. **Prioritize pseudocode** - Express core algorithms with flowcharts or pseudocode

## Notes

- This skill performs **read-only** operations
- Documents are generated directly after language detection
- Supports cross-project multi-PR analysis
- Language preference is remembered within the session
- For complex cross-repository dependencies, consider splitting into multiple documents
