# Skills

MASTER skills live as flat markdown files under MASTER/data/skills, each named *.md. Every skill declares YAML frontmatter with name, description, and triggers (or patterns for pattern-based activation). An optional skill.rb may sit beside the markdown when a skill needs executable behavior beyond the prose contract.

The registry reloads before each prompt, so new or edited skills take effect without restarting MASTER. Frontmatter structure stays consistent across files so dispatch and tooling can scan the directory predictably.