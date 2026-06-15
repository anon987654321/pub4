# encoding: utf-8
# Command handler for parsing and executing user commands.

require "langchain"
require_relative "filesystem_tool"
require_relative "prompt_manager"
require_relative "memory_manager"

class CommandHandler
  def initialize(langchain_client)
    @prompt_manager = PromptManager.new
    @filesystem_tool = FileSystemTool.new
    @memory_manager = MemoryManager.new
    @langchain_client = langchain_client
  end

  def handle_input(input)
    command, params = input.split(" ", 2)
    case command
    when "read"
      @filesystem_tool.read_file(params)
    when "write"
      content = get_user_content
      @filesystem_tool.write_file(params, content)
    when "delete"
      @filesystem_tool.delete_file(params)
    when "prompt"
      handle_prompt_command(params)
    else
      "Command not recognized."
    end
  end

  private

  def handle_prompt_command(params)
    prompt_key = params.to_sym
    if @prompt_manager.prompts.key?(prompt_key)
      vars = collect_prompt_variables(prompt_key)
      @prompt_manager.format_prompt(prompt_key, vars)
    else
      "Prompt not found."
    end
  end

  def collect_prompt_variables(prompt_key)
    prompt = @prompt_manager.get_prompt(prompt_key)
    prompt.input_variables.each_with_object({}) do |var, vars|
      puts "Enter value for #{var}:"
      vars[var] = gets.strip
    end
  end

  def get_user_content
    # Assume this function collects further input from the user
  end
end
