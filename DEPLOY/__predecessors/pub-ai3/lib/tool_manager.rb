# lib/tool_manager.rb
#
# ToolManager: Handles execution of integrated tools.
# Loads available tools from the "tools" subdirectory.

require_relative "tools/filesystem_tool"
require_relative "tools/universal_scraper"

class ToolManager
  TOOLS = {
    "filesystem" => FilesystemTool.new,
    "scraper" => UniversalScraper.new
  }

  def run_tool(tool_name, *args)
    tool = TOOLS[tool_name.downcase]
    return "Tool not found" unless tool

    tool.execute(*args)
  rescue StandardError => e
    "Error executing tool: #{e.message}"
  end
end

