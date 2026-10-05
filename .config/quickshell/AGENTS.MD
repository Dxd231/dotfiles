# Agent Directives: Search-First Grounding & Verification

## Core Policy: Proactive Web Search
You have access to web search capabilities. Do not rely solely on internal memory or parametric weights for third-party tools, frameworks, and fast-evolving libraries. Treat web search as a primary verification layer.

### Mandatory Search Triggers
You MUST invoke web search before generating code or answering in the following scenarios:
1. **Third-Party APIs & Libraries**: Whenever using or updating modern frameworks, SDKs, or npm/pip/cargo packages (especially APIs, configuration schemas, or CLI syntax). Never invent or guess function signatures, parameters, or configurations.
2. **Errors & Debugging**: When diagnosing non-trivial runtime exceptions, compiler/linter errors, or ambiguous stack traces. Search the exact error string and relevant package name.
3. **Breaking Changes & Version Migration**: When dealing with major library version bumps, deprecated methods, or modern language features.
4. **Best Practices & Tooling**: When recommending architectural design patterns, setup scripts, or CI/CD pipelines.

### Verification & Anti-Hallucination Rules
- **No API Guessing**: If you are not 100% confident in a method's signature or a configuration key's current schema, search for official documentation before writing code.
- **Query Strategy**: Run crisp, targeted queries focusing on official docs, GitHub issues, or release notes (e.g., `"<library>" v<major_version> <feature> documentation`, `"<error_message>" <framework>`).
- **Grounding**: Ensure code suggestions reflect the latest stable syntax, not legacy or deprecated patterns.

### Execution Workflow
1. **Analyze**: Identify dependencies, third-party symbols, or errors that require verification.
2. **Search**: Issue search queries to fetch current documentation or confirmed issue resolutions.
3. **Synthesize & Act**: Apply verified patterns to local codebase edits and command executions.
