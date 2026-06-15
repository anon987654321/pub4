AI^3 CLI
AI^3 is a modular command-line interface (CLI) built in Ruby,
leveraging LangChain.rb for multi-LLM integration,
retrieval-augmented generation (RAG),
and role-specific assistants. It runs on OpenBSD with secure execution (pledge/unveil) and supports Ruby 3.2+.
Features

Interactive CLI: Launch with ruby ai3.rb for a TTY-based interface.
Multi-LLM Support: Integrates with Grok, Claude, OpenAI, and Ollama.
RAG: Uses Weaviate for context-aware responses.
15 Assistants: Specialized roles (e.g., General, Lawyer, Hacker, Medical).
UniversalScraper: Ferrum-based scraper with page source and screenshots.
Multimedia: Manages Replicate.com AI models for TV/news broadcasting.
FileUtils: Grants LLMs command-line access, including root via doas.
Security: OpenBSD pledge/unveil, encrypted sessions.
Localization: Supports multiple languages via I18n.
Caching: Stores LLM responses, scraped data, and multimedia outputs.

Installation
Prerequisites

OpenBSD (required for pledge/unveil and doas)
Ruby 3.2+
zsh for installation scripts
Optional: API keys for XAI, Anthropic, OpenAI, Replicate
Optional: Weaviate instance for RAG

Steps

Clone the repository:git clone <repository_url>
cd ai3


Run the core installation script:./install.sh


Installs Ruby gems via Gemfile.
Prompts for API keys (stored in ~/.ai3_keys).
Sets ai3.rb as executable.


Install assistants:./install_ass.sh


Generates 15 assistant Ruby files in assistants/.
Configures config.yml and en.yml.



Post-Installation

Run the CLI:ruby ai3.rb



Usage
Launch the interactive CLI with ruby ai3.rb. Available commands:

chat <query>: Chat with an assistant (e.g., chat What is AI?).
task <name> [args]: Run a task (e.g., task analyze_market Bitcoin).
rag <query>: Perform a RAG query (e.g., rag Norwegian laws).
list: List available assistants.
help: Show help.
exit: Exit the CLI.

Assistants



Assistant
Role
Example Command



General
General-purpose queries
chat Explain quantum computing


OffensiveOps
Sentiment trend analysis
chat Analyze news sentiment


Influencer
Social media content curation
chat Curate Instagram posts


Lawyer
Legal research
rag Norwegian data privacy laws


Trader
Cryptocurrency analysis
task analyze_market Ethereum


Architect
Parametric design
chat Explore sustainable designs


Hacker
Ethical hacking
chat Find Apache vulnerabilities


ChatbotSnapchat
Snapchat engagement
chat Engage Snapchat users


ChatbotOnlyfans
OnlyFans engagement
chat Engage OnlyFans users


Personal
Task management
chat Schedule my day


Music
Music creation
chat Compose a jazz track


MaterialRepurposing
Repurposing ideas
chat Repurpose plastic bottles


SEO
Web optimization
chat Optimize blog for SEO


Medical
Medical research
rag Latest on Alzheimer’s


PropulsionEngineer
Propulsion analysis
chat Analyze rocket engines


LinuxOpenbsdDriverTranslator
Driver translation
chat Translate Linux driver


Advanced Features

UniversalScraper: Uses Ferrum to scrape web content, capturing page source and screenshots to determine depth.
Multimedia: Combines Replicate.com’s AI models for TV/news broadcasting (e.g., real-time visuals, automated scripts).
FileUtils: Allows LLMs to:
Execute system commands (e.g., doas su for root access).
Browse the internet via UniversalScraper.
Complete projects (e.g., generate code, manage files).
Speculative: Orchestrate 3D printing of exoskeletons.



Configuration
Edit config.yml to customize:

LLM Settings: Primary/secondary LLMs, temperature, max tokens.
RAG: Weaviate host, index name, sources.
Scraper: Max depth, timeout, screenshot directory.
Multimedia: Model cache, output directory.
FileUtils: Root access, command timeout, max file size.
Assistants: Tools, URLs, default goals.

Example:
llm:
  primary: "xai"
  temperature: 0.6
scraper:
  max_depth: 2
  timeout: 30
multimedia:
  output_dir: "data/models/multimedia"
assistants:
  general:
    role: "General-purpose assistant"
    default_goal: "Explore diverse topics"

Development
Dependencies
Install gems via Gemfile:
bundle install

Directory Structure
ai3/
├── ai3.rb                # Interactive CLI
├── assistants/           # Assistant Ruby files
├── config/
│   ├── config.yml        # Configuration
│   └── locales/en.yml    # Localization
├── lib/
│   ├── cognitive.rb      # Shared logic
│   ├── multimedia.rb     # Replicate model management
│   ├── scraper.rb        # UniversalScraper
│   ├── mock_classes.rb   # Mock dependencies
│   └── utils/
│       ├── config.rb     # Config loader
│       ├── file.rb       # File and system operations
│       └── llm.rb        # LLM utilities
├── data/                 # Cache, vector DB, models, screenshots
├── logs/                 # Logs
├── tmp/                  # Temporary files
├── install.sh            # Core installer
├── install_ass.sh        # Assistants installer
├── Gemfile               # Dependencies
└── README.md             # Documentation

Adding Assistants

Create a new Ruby file in assistants/ (e.g., new_assistant.rb):# frozen_string_literal: true

require_relative "base_assistant"
require_relative "../lib/cognitive"

class NewAssistant < BaseAssistant
  include Cognitive

  def initialize
    super("new_assistant")
    set_goal(AI3::Config.instance["assistants"]["new_assistant"]["default_goal"])
  end

  def respond(input)
    decrypted_input = AI3.session_manager.decrypt(input)
    pursue_goal if rand < 0.2
    AI3.with_retry do
      response = @agent.run(decrypted_input)
      AI3.session_manager.encrypt(AI3.summarize(response))
    end
  end
end


Update config.yml:assistants:
  new_assistant:
    role: "New assistant role"
    llm: "grok"
    tools: ["SystemTool"]
    urls: ["https://example.com"]
    default_goal: "Explore new topics"


Run install_ass.sh to regenerate assistants.

Security

OpenBSD: Uses pledge/unveil to restrict system calls and file access.
Root Access: Enabled via doas for network diagnostics, system modifications.
Encryption: Session data encrypted via SessionManager.
Ethics: Input checked for unethical content.

Troubleshooting

LLM Errors: Ensure API keys are set in ~/.ai3_keys.
Weaviate Issues: Verify Weaviate is running at the configured host.
Scraper Issues: Check Ferrum installation and network connectivity.
Logs: Check logs/ai3.log for errors.

License
MIT License. See LICENSE for details.
Contact
For support, contact the AI^3 team at support@ai3.example.com.