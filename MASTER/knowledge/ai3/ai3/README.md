# AI^3: Advanced Intelligent Integration Interface

AI^3 ("Ai-Ai-Ai"), developed by [PubHealthcare](https://pub.healthcare/), is a pioneering platform transforming **healthcare**, **architecture**, **urban planning**, **scientific research**, and **personal protection**. Built with [Ruby](https://www.ruby-lang.org/en/) and [LangChain.rb](https://github.com/patterns-ai-core/langchainrb), **AI^3** integrates advanced AI models like [ChatGPT](https://openai.com/chatgpt), [Anthropic Claude](https://www.anthropic.com/product/claude), and [Replicate](https://replicate.com/) into Unix environments and a **mobile-first Rails Progressive Web App (PWA)**. This integration drives global advancements across sectors, offering a robust CLI for OpenBSD and a unified PWA designed to act as a personal assistant, safeguarding users.

---

## Key Features

### 1. Multi-LLM Support
AI^3 integrates multiple LLMs, including OpenAI's GPT-4, Claude, and Replicate, to handle diverse use cases such as text summarization, context-based querying, and dynamic task execution.

### 2. Weaviate-Powered Memory
Utilizes Weaviate as a vector database for context persistence and retrieval in RAG (Retrieval-Augmented Generation) workflows.

### 3. Modular Tools
AI^3 includes and supports:
- **Calculator**: Perform complex calculations on demand.
- **File Search**: Efficiently search and retrieve files.
- **Weather Tool**: Fetch and present real-time weather information.
- **Universal Scraper**: Smart human-like scraping with Ferrum.

### 4. Secure Execution
Implements OpenBSD's `pledge` and `unveil` for secure and isolated runtime environments.

### 5. Context-Aware Memory
Maintains interaction history to enable coherent and continuous workflows, adapting seamlessly to user needs.

### 6. CLI and PWA Integration
A robust CLI and mobile-first Rails PWA ensure accessibility and functionality across platforms, enabling users to harness AI^3's capabilities on both Unix systems and mobile devices.

---

## Applications

### 🏥 Healthcare
AI^3 optimizes patient care and resource management with predictive diagnostics, enhanced telemedicine, and secure consultations for remote regions.

### 🏙️ Urban Renewal
Supports sustainable construction with swarm robotics, traffic management innovations, and green design principles to develop eco-friendly, pedestrian-centric spaces.

### 🔬 Scientific Research
Facilitates superscale molecular simulations and cross-disciplinary advancements in personalized medicine and atomic research.

### 🛡️ Security and Defense
Enhances surveillance and countermeasure capabilities, disrupts disinformation, and provides constant vigilance for defense and security agencies.

### 📱 Personal Protection
Acts as a personal assistant to detect threats, coordinate emergency responses, and safeguard privacy with advanced encryption.

---

## Installation and Setup

### Prerequisites
1. Ruby 3.0+
2. Environment variables:
   - `OPENAI_API_KEY`: API key for OpenAI.
   - `WEAVIATE_HOST` and `WEAVIATE_API_KEY`: Configuration for Weaviate.

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/your-repo/ai3.git
   cd ai3
   ```
2. Install dependencies:
   ```bash
   bundle install
   ```
3. Configure environment variables:
   ```bash
   export OPENAI_API_KEY=your_openai_api_key
   export WEAVIATE_HOST=your_weaviate_host
   export WEAVIATE_API_KEY=your_weaviate_api_key
   ```
4. Run the main script:
   ```bash
   ruby ai3.rb
   ```

---

## Usage

### CLI Commands
- **Chat with the assistant**:
  ```bash
  ruby ai3.rb --chat "What is the weather like today?"
  ```

- **Run a predefined task**:
  ```bash
  ruby ai3.rb --task "greet_user" --args "John"
  ```

### Adding Tools
Tools can be dynamically added to the assistant:
```ruby
ai3 = AI3.new
ai3.add_tool(MyCustomTool.new)
```

### RAG Workflow
AI^3 supports retrieval-augmented generation with seamless integration of Weaviate:
```ruby
response = ai3.rag_query("Explain quantum physics.")
puts response
```

---

## Vision

**AI^3** aims to:

- **🌆 Transform Urban Infrastructure**: Build sustainable, adaptable cities.
- **🏥 Advance Global Healthcare**: Implement efficient, AI-driven care systems.
- **🔬 Enhance Research Frontiers**: Bridge diverse fields to drive societal progress.
- **🛡️ Strengthen Defense and Security**: Equip NATO and allied forces with advanced AI tools to maintain global peace and security.
- **📱 Empower Personal Protection**: Provide individuals with AI-driven personal assistants to enhance safety and well-being.

---

## Why LangChain?
LangChain’s flexible design enhances AI^3 by enabling seamless integration and intelligent data handling. It connects with APIs and tools, interacts robustly with vector databases for smart data management, and scales effectively for complex workflows. This ensures AI^3 remains adaptable to evolving technological and user needs.

---

## Contributing
Contributions are welcome! Please submit a pull request or raise an issue for feature requests and bug fixes.

---

## License
This project is licensed under the MIT License.

