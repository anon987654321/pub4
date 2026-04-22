ai_recruitment_agent_team/
├─ lib/                     # Core Master framework (shared across all demos)
├─ agents/                  # Concrete agent implementations
│   ├─ researcher.rb        # discovers talent pools, parses resumes
│   ├─ screener.rb          # runs initial qualification checks
│   ├─ scorer.rb            # ranks candidates against a role profile
│   └─ writer.rb            # crafts personalized outreach messages
├─ prompts/                 # Prompt templates (YAML) for each role
│   ├─ researcher.yml
│   ├─ screener.yml
│   ├─ scorer.yml
│   └─ writer.yml
├─ config.yml               # Team configuration – model, temperature, budget, etc.
├─ requirements.txt         # Optional Python dependencies for data wrangling
└─ README.md                # You are reading it now
