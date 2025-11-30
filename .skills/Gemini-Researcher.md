# Gemini CLI - The Researcher

## Purpose
Gemini has a 1M+ token context window. Use it for all code analysis, architecture review, and bug tracing.

## Usage
```bash
.skills/gemini.agent.wrapper.sh -d "@directory/" "Your detailed prompt"
```

## Large Directory Warning
Directories with >500 files will cause `EMFILE` errors. Use grep to narrow scope first, then analyze specific subdirectories.

## Writing Effective Prompts

**Every prompt should specify exactly what you need.** Gemini works best with detailed, structured requests.

### Template: Feature Analysis
```bash
.skills/gemini.agent.wrapper.sh -d "@src/" "
TASK: Explain how [feature] is implemented.

REQUIREMENTS:
1. List all files involved with full paths and line numbers
2. Show the data flow from entry point to completion
3. Include relevant code excerpts (not summaries)
4. Identify external dependencies
5. Note any edge cases or error handling

OUTPUT FORMAT:
- Start with a one-paragraph summary
- Then provide detailed file-by-file breakdown
- End with architectural observations
"
```

### Template: Bug Investigation
```bash
.skills/gemini.agent.wrapper.sh -d "@src/" "
BUG: [Description of the problem]
LOCATION: [File:line if known]
ERROR MESSAGE: [Exact error if available]

INVESTIGATE:
1. Trace the execution path that leads to this bug
2. Identify the root cause (not just the symptom)
3. List all files in the call stack with line numbers
4. Show the problematic code and explain why it fails
5. Check for similar patterns elsewhere that might have the same issue

PROVIDE:
- Root cause explanation
- Affected files with specific line numbers
- Recommended fix with minimal code changes
- Potential regression risks
"
```

### Template: Pre-Implementation Research
```bash
.skills/gemini.agent.wrapper.sh -d "@src/" "
GOAL: I need to implement [feature description].

ANALYZE:
1. What existing patterns in this codebase should I follow?
2. Which files will need modification? List with paths.
3. What dependencies or services will be affected?
4. Show examples of similar implementations in this codebase
5. What tests exist that I should update or use as templates?

OUTPUT:
- Implementation approach recommendation
- File modification checklist with specific locations
- Code examples from existing codebase to follow
- Risk assessment
"
```

### Template: Code Review
```bash
.skills/gemini.agent.wrapper.sh -d "@src/" "
REVIEW THESE CHANGES:
- [File1]: [What changed]
- [File2]: [What changed]

CHECK FOR:
1. Architectural consistency with existing patterns
2. Security vulnerabilities (injection, auth bypass, data exposure)
3. Performance implications (N+1 queries, memory leaks, blocking calls)
4. Error handling completeness
5. Edge cases not covered
6. Breaking changes to existing functionality

OUTPUT:
- Issues found with severity rating (critical/high/medium/low)
- Specific file:line references for each issue
- Recommended fixes
- Approval status
"
```

### Template: Pattern Search
```bash
.skills/gemini.agent.wrapper.sh -d "@src/" "
FIND: All instances of [pattern/implementation type].

FOR EACH OCCURRENCE:
1. File path and line number
2. Code excerpt (3-5 lines of context)
3. How it's being used
4. Any variations or inconsistencies

SUMMARIZE:
- Total count
- Common patterns vs outliers
- Recommendations for standardization if applicable
"
```

### Template: Architecture Audit
```bash
.skills/gemini.agent.wrapper.sh -d "@src/" "
AUDIT: [Specific aspect - e.g., authentication, data persistence, API layer]

ANALYZE:
1. Current architecture and design patterns used
2. Data flow diagrams (describe in text)
3. Dependencies between components
4. Security considerations
5. Scalability implications

IDENTIFY:
- Strengths of current approach
- Weaknesses or technical debt
- Missing error handling
- Potential failure points
- Recommendations for improvement (prioritized)

Provide specific file:line references for all findings.
"
```

## Prompt Best Practices

1. **Be specific** - "How is JWT validation implemented?" not "How does auth work?"
2. **Request structure** - Always specify the output format you need
3. **Include context** - Mention related files, error messages, or constraints
4. **Ask for code** - Request actual code excerpts, not summaries
5. **Require line numbers** - Always ask for file:line references
6. **Set scope** - Specify which directories/files to analyze

## Quick Commands
```bash
# Understand implementation
.skills/gemini.agent.wrapper.sh -d "@src/" "How is [feature] implemented? Include file paths, line numbers, and code excerpts."

# Find files
.skills/gemini.agent.wrapper.sh -d "@src/" "Which files handle [functionality]? List all with their responsibilities."

# Trace execution
.skills/gemini.agent.wrapper.sh -d "@src/" "Trace the execution flow from [entry point] to [outcome]. Show each step with file:line."

# Security check
.skills/gemini.agent.wrapper.sh -d "@src/" "Review [files/feature] for security vulnerabilities. List findings with severity and file:line."

# Pre-change analysis
.skills/gemini.agent.wrapper.sh -d "@src/" "I'm about to modify [file]. What depends on it? What might break?"
```
