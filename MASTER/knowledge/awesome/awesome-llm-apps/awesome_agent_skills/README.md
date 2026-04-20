
### ManualClone or download skill directories and reference them in your agent’s configuration.

## Usage

Skills become available after installation. Agents use them when a task matches a skill’s description or triggers.

### Examples- **"Review this React component for performance"** → activates `code-reviewer`
- **"Research the benefits of intermittent fasting"** → activates `deep-research`
- **"Help me debug this Python function"** → activates `debugger`
- **"Draft an email to decline a meeting"** → activates `email-drafter`

## Integration with Agent Products

Agent Skills work with any skills‑compatible agent product, including:

- Claude Desktop / claude.ai – upload `SKILL.md` to project knowledge
- Cursor / VSCode – reference skills in `.cursorrules` or custom instructions- Custom agents – load `SKILL.md` as system prompts or agent instructions
- AI frameworks – use with LangChain, AutoGen, or custom frameworks

## Skill Structure

Each skill follows the Agent Skills specification:

