# encoding: utf-8
# Manages dynamic prompts for the system

require "langchain"

class PromptManager
  attr_accessor :prompts

  def initialize
    @prompts = {
      rules: Langchain::Prompt::PromptTemplate.new(
        template: rules_template,
        input_variables: []
      ),
      analyze: Langchain::Prompt::PromptTemplate.new(
        template: analyze_template,
        input_variables: []
      ),
      develop: Langchain::Prompt::PromptTemplate.new(
        template: develop_template,
        input_variables: []
      ),
      finalize: Langchain::Prompt::PromptTemplate.new(
        template: finalize_template,
        input_variables: []
      ),
      testing: Langchain::Prompt::PromptTemplate.new(
        template: testing_template,
        input_variables: []
      )
    }
  end

  def get_prompt(key)
    @prompts[key]
  end

  def format_prompt(key, vars = {})
    prompt = get_prompt(key)
    prompt.format(vars)
  end

  private

  def rules_template
    <<~TEMPLATE
      # RULES

      The following rules must be enforced regardless **without exceptions**:

      1. **Retain all content**: Do not delete anything unless explicitly marked as redundant.
      2. **Full content display**: Do not truncate, omit, or simplify any content. Always read/display the full version. Vital to **ensure project integrity**.
      3. **No new features without approval**: Stick to the defined scope.
      4. **Data accuracy**: Base answers on actual data only; do not make assumptions or guesses.

      ## Formatting

      - Use **double quotes** instead of single quotes.
      - Use **two-space indents** instead of tabs.
      - Use **underscores** instead of dashes.
      - Enclose code blocks in **quadruple backticks** to avoid code falling out of their code blocks.

      ## Standards

      - Write **clean, semantic, and minimalistic** Ruby, JS, HTML5 and SCSS.
      - Use Rails' **tag helper** (`<%= tag.p "Hello world" %>`) instead of standard HTML tags.
      - **Split code into partials** and avoid nested divs.
      - **Use I18n with corresponding YAML files** for translation into English and Norwegian, i.e., `<%= t("hello_world") %>`.
      - Sort CSS rules **by feature, and their properties/values alphabetically**. Use modern CSS like **flexbox** and **grid layouts** instead of old-style techniques like floats, clears, absolute positioning, tables, inline styles,  vendor prefixes, etc. Additionally, make full use of the syntax and features in SCSS.

      **Non-compliance with these rules can cause significant issues and must be avoided.**
    TEMPLATE
  end

  def analyze_template
    <<~TEMPLATE
      # ANALYZE

      - **Complete extraction**: Extract and read all content in the attachment(s) without truncation or omission.
      - **Thorough analysis**: Analyze every line meticulously, cross-referencing each other with related libraries and knowledge for deeper understanding and accuracy.
      - Start with **README.md** if present.
      - **Silent processing**: Keep all code and analysis results to yourself (in quiet mode) unless explicitly requested to share or summarize.
    TEMPLATE
  end

  def develop_template
    <<~TEMPLATE
      # DEVELOP

      - **Iterative development**: Improve logic over multiple iterations until requirements are met.
        1. **Iteration 1**: Implement initial logic.
        2. **Iteration 2**: Refine and optimize.
        3. **Iteration 3**: Add comments to code and update README.md.
        4. **Iteration 4**: Refine, streamline and beautify.
        5. **Additional iterations**: Continue until satisfied.

      - **Bug-fixing**: Identify and fix bugs iteratively until stable.

      - **Code quality**:
        - **Review**: Conduct peer reviews for logic and readability.
        - **Linting**: Enforce coding standards.
        - **Performance**: Ensure efficient code.
    TEMPLATE
  end

  def finalize_template
    <<~TEMPLATE
      # FINALIZE

      - **Consolidate all improvements** from this chat into the **Zsh install script** containing our **Ruby (Ruby On Rails)** app.
      - Show **all shell commands needed** to generate and configure its parts. To create new files, use **heredoc**.
      - Group the code in Git commits logically sorted by features and in chronological order**.
      - All commits should include changes from previous commits to **prevent data loss**.
      - Separate groups with `# -- <UPPERCASE GIT COMMIT MESSAGE> --\n\n`.
      - Place everything inside a **single** codeblock. Split it into chunks if too big.
      - Refine, streamline and beautify, but without over-simplifying, over-modularizating or over-concatenating.
    TEMPLATE
  end

  def testing_template
    <<~TEMPLATE
      # TESTING

      - **Unit tests**: Test individual components using RSpec.
        - **Setup**: Install RSpec, and write unit tests in the `spec` directory.
        - **Guidance**: Ensure each component's functionality is covered with multiple test cases, including edge cases.

      - **Integration tests**: Verify component interaction using RSpec and FactoryBot.
        - **Setup**: Install FactoryBot, configure with RSpec, define factories, and write integration tests.
        - **Guidance**: Test interactions between components to ensure they work together as expected, covering typical and complex interaction scenarios.
    TEMPLATE
  end
end
