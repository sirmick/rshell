# RShell Documentation Index

A comprehensive guide to all RShell documentation, organized by category.

**Last Updated**: 2025-11-23

---

## Getting Started

Start here if you're new to RShell:

| Document | Purpose | Lines |
|----------|---------|------:|
| [README.md](README.md) | Project overview, features, installation | 532 |
| [START_HERE.md](START_HERE.md) | Developer onboarding, architecture tour | 319 |
| [BUILD.md](BUILD.md) | Build instructions, native dependencies | 314 |

---

## Core Design Documents

Architectural decisions and system design:

| Document | Purpose | Lines |
|----------|---------|------:|
| [ARCHITECTURE_DESIGN.md](ARCHITECTURE_DESIGN.md) | System architecture, component relationships | 692 |
| [RUNTIME_DESIGN.md](RUNTIME_DESIGN.md) | Runtime execution model, context management | 334 |
| [EXECUTION_FRAME_DESIGN.md](EXECUTION_FRAME_DESIGN.md) | Frame stack, scope management, output isolation | 1037 |

---

## Feature Design Documents

Specific feature implementations:

| Document | Purpose | Lines |
|----------|---------|------:|
| [BUILTIN_DESIGN.md](BUILTIN_DESIGN.md) | Builtin commands, namespace system, I/O design | 1281 |
| [CONTROL_FLOW_DESIGN.md](CONTROL_FLOW_DESIGN.md) | If/for/while/case statements | 1095 |
| [ENV_VAR_DESIGN.md](ENV_VAR_DESIGN.md) | Environment variables, native types, bracket notation | 1326 |
| [RSHELL_SYNTAX_DESIGN.md](RSHELL_SYNTAX_DESIGN.md) | RShell syntax specification, extensions to bash | 740 |
| [PIPELINE_DESIGN.md](PIPELINE_DESIGN.md) | Future: pipelines, redirects (not yet implemented) | 815 |
| [READLINE_SUPPORT.md](READLINE_SUPPORT.md) | Readline integration, line editing | 344 |

---

## Testing Documentation

How to write and understand tests:

| Document | Purpose | Lines |
|----------|---------|------:|
| [TEST_GUIDE.md](TEST_GUIDE.md) | Testing patterns, CLIHelper usage, best practices | 725 |
| [UNIT_TESTS.md](UNIT_TESTS.md) | Unit test coverage documentation | 502 |

---

## Grammar and Parsing

Tree-sitter grammar implementation (in rshell-grammar/):

| Document | Purpose | Lines |
|----------|---------|------:|
| [rshell-grammar/README.md](rshell-grammar/README.md) | Grammar overview, building, testing | ~200 |
| [rshell-grammar/STATUS.md](rshell-grammar/STATUS.md) | Current implementation status | ~150 |
| [rshell-grammar/PARSER_DESIGN.md](rshell-grammar/PARSER_DESIGN.md) | Parser architecture and design | ~300 |
| [rshell-grammar/tests/README.md](rshell-grammar/tests/README.md) | Grammar test suite documentation | ~100 |

---

## AI Assistant Guidance

| Document | Purpose | Lines |
|----------|---------|------:|
| [PROMPT.md](PROMPT.md) | Instructions for AI assistants working on RShell | ~200 |

---

## Documentation Cleanup

| Document | Purpose | Lines |
|----------|---------|------:|
| [DOCUMENTATION_CLEANUP_PLAN.md](DOCUMENTATION_CLEANUP_PLAN.md) | Analysis and cleanup plan (2025-11-23) | ~400 |

---

## Quick Navigation by Topic

### Understanding the System
1. Read [START_HERE.md](START_HERE.md) for overview
2. Read [ARCHITECTURE_DESIGN.md](ARCHITECTURE_DESIGN.md) for system design
3. Read [RUNTIME_DESIGN.md](RUNTIME_DESIGN.md) for execution model

### Implementing Features
- **Builtins**: [BUILTIN_DESIGN.md](BUILTIN_DESIGN.md)
- **Control Flow**: [CONTROL_FLOW_DESIGN.md](CONTROL_FLOW_DESIGN.md)
- **Variables**: [ENV_VAR_DESIGN.md](ENV_VAR_DESIGN.md)
- **Syntax**: [RSHELL_SYNTAX_DESIGN.md](RSHELL_SYNTAX_DESIGN.md)

### Writing Tests
1. Read [TEST_GUIDE.md](TEST_GUIDE.md) for patterns and best practices
2. Reference [UNIT_TESTS.md](UNIT_TESTS.md) for existing coverage

### Building and Installing
1. Read [BUILD.md](BUILD.md) for build instructions
2. Read [README.md](README.md) for installation

### Grammar Development
1. Read [rshell-grammar/README.md](rshell-grammar/README.md) for overview
2. Read [rshell-grammar/PARSER_DESIGN.md](rshell-grammar/PARSER_DESIGN.md) for architecture
3. Check [rshell-grammar/STATUS.md](rshell-grammar/STATUS.md) for current state

---

## Document Status

### Current and Maintained ✅

All documents listed above are current and actively maintained (as of 2025-11-23).

### Completed Migrations

The following design documents described migrations that are now complete:
- ~~BUILTIN_EXECUTION_STATE_DESIGN.md~~ - Deleted (migration complete, 98.9% tests passing)
- ~~RSHELL_HARD_CUTOVER_PLAN.md~~ - Would be archived if existed (cutover complete)
- ~~EXECUTION_FRAME_STATUS.md~~ - Would be archived if existed (status now in design doc)
- ~~EXECUTION_STATE_MIGRATION.md~~ - Would be archived if existed (migration complete)

### Historical Documents

Historical planning and status tracking documents have been moved to:
- `rshell-grammar/archive/obsolete_docs/` - Grammar-related historical docs

---

## Contribution Guidelines

When adding new documentation:

1. **Choose the right place**:
   - Core architecture → Add section to existing design doc
   - New feature → Create new `*_DESIGN.md` file
   - Implementation guide → Add to appropriate design doc
   - Testing → Update [TEST_GUIDE.md](TEST_GUIDE.md) or [UNIT_TESTS.md](UNIT_TESTS.md)

2. **Update this index**: Add your document to the appropriate section

3. **Cross-reference**: Link to related documents using `[name](path)`

4. **Include line count**: Helps readers gauge document size

5. **Keep status current**: Mark completed migrations, archive obsolete docs

---

## Total Documentation

**Root Directory**: 16 markdown files (~8,000 lines)  
**Grammar Subdirectory**: 4 markdown files (~750 lines)  
**Total**: 20 active documentation files

---

**Next Steps**: See [START_HERE.md](START_HERE.md) to begin exploring RShell.