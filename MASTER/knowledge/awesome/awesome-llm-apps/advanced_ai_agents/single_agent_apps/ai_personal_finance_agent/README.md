ai_personal_finance_agent/
├── README.md          # ← you are here
├── agent.rb           # Master::Agent subclass implementing finance‑specific logic
├── config.yml         # Model, prompt and tool configuration
└── tools/
    ├── read_file.rb   # Safe text file reader (uses Master::Security::InjectionGuard)
    ├── write_file.rb  # Safe writer with directory whitelisting
    └── web_search.rb  # Search the web via Master::Tools::WebSearch
