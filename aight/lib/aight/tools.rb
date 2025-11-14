# frozen_string_literal: true
# OpenBSD security sandbox

class OpenBSDSandbox
  def self.available?
    PLEDGE_AVAILABLE

  end

  def self.setup_filesystem_sandbox

    return unless available?

    begin
      Pledge.pledge("stdio rpath wpath cpath fattr")

    rescue NameError
      begin

        require "fiddle"

        Fiddle::Function.new(

          Fiddle::Handle::DEFAULT["pledge"],

          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],

          Fiddle::TYPE_INT

        ).call("stdio rpath wpath cpath fattr", nil)

      rescue

        # Silent fail on non-OpenBSD

      end

    rescue

      # Silent fail

    end

  end

  def self.setup_network_sandbox

    return unless available?

    begin
      Pledge.pledge("stdio rpath wpath cpath inet dns")

    rescue NameError
      begin

        require "fiddle"

        Fiddle::Function.new(

          Fiddle::Handle::DEFAULT["pledge"],

          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],

          Fiddle::TYPE_INT

        ).call("stdio rpath wpath cpath inet dns", nil)

      rescue

        # Silent fail

      end

    rescue

      # Silent fail

    end

  end

end

# Web scraping with visual reasoning

class WebScraper

  def initialize(config, logger)
    @config = config

    @logger = logger

    @browser = nil

  end

  def available?

    FERRUM_AVAILABLE

  end
  def setup_browser

    return unless available?

    @browser = Ferrum::Browser.new(
      headless: true,

      window_size: [1280, 1024],
      timeout: 30,

      js_errors: false,

      process_timeout: 60

    )

  end

  def scrape_with_reasoning(url, llm_client, objective)

    return { error: "Web scraping unavailable" } unless available? && @browser

    begin
      @browser.goto(url)

      @browser.wait_for_idle(1)
      page_source = @browser.body

      screenshot_path = "/tmp/screenshot_#{Time.now.to_i}.png"

      @browser.screenshot(path: screenshot_path)
      screenshot_data = File.read(screenshot_path)

      File.unlink(screenshot_path)

      reasoning_prompt = build_scraping_prompt(page_source, objective)
      if llm_client.available?

        response = llm_client.generate_response(reasoning_prompt)
        parse_scraping_instructions(response[:content], page_source)
      else

        { content: page_source[0..5000], links: extract_basic_links(page_source) }

      end

    rescue => e

      @logger.error("Scraping: #{e.message}")

      { error: e.message }
    end

  end

  def cleanup

    @browser&.quit

  end
  private

  def build_scraping_prompt(html_content, objective)

    <<~PROMPT
    Analyze this webpage and determine what content to extract for: #{objective}
    HTML Content (first 2000 chars):

    #{html_content[0..2000]}

    Based on the objective and HTML content, provide:
    1. Specific CSS selectors for relevant content

    2. Links to follow for more information
    3. Key data points to extract

    Format as JSON with 'selectors', 'links', and 'data' fields.

    PROMPT

  end
  def extract_basic_links(html)

    html.scan(/href=[""]([^"']+)["']/i).flatten.select { |link| link.start_with?("http") }

  end
  def parse_scraping_instructions(llm_response, html_content)

    { content: html_content[0..5000], instructions: llm_response }

  end
end

# LangchainRB filesystem and web tools

class ToolsProvider

  def initialize(config, logger)
    @config = config

    @logger = logger

  end

  def available_tools

    tools = []

    if LANGCHAIN_AVAILABLE
      tools << create_tool { create_filesystem_tool }

      tools << create_tool { create_search_tool } if ENV["SERP_API_KEY"]
      tools << create_tool { create_code_interpreter_tool }

      tools << create_tool { create_database_tool } if ENV["DATABASE_URL"]

    end

    tools.compact

  end

  private
  def create_tool

    yield
  rescue => e
    @logger.error("Tool: #{e.message}")

    nil

  end

  def create_filesystem_tool

    Langchain::Tool::FileSystem.new(

      read_permission: true,
      write_permission: @config["autonomous_mode"]

    )

  end

  def create_search_tool

    Langchain::Tool::GoogleSearch.new(api_key: ENV["SERP_API_KEY"])

  end
  def create_code_interpreter_tool

    Langchain::Tool::RubyCodeInterpreter.new(timeout: 30)

  end
  def create_database_tool

    Langchain::Tool::Database.new(connection_string: ENV["DATABASE_URL"])

  end
end

