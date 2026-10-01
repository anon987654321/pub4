# frozen_string_literal: true

require_relative "test_helper"

class TestCliWebParity < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path), encoding: "UTF-8")
  end

  def test_browser_command_palette_comes_from_command_registry
    view = read("web/app/views/chat/index.html.erb")
    js = read("web/public/chat.js")

    assert_includes view, "window.MASTER_COMMANDS"
    assert_includes view, "CommandRegistry.command_surface"
    refute_match(/const COMMANDS = \\[/, js)
    assert_includes js, "(window.MASTER_COMMANDS || [])"
  end

  def test_browser_slash_commands_use_the_shared_turn_stream
    actions = read("web/public/chat_actions.js")

    assert_includes actions, "function sendMessage(text, { command = false } = {})"
    assert_includes actions, 'function runUnlockCommand(text)'
    assert_includes actions, 'fetch("/chat/command"'
  end

  def test_cli_and_web_use_one_result_presenter
    cli = read("lib/cli/session/result_display.rb")
    web = read("web/app/services/chat_service.rb")

    assert_includes cli, "Master::CLI::TurnPresentation.success_text"
    assert_includes cli, "Master::CLI::TurnPresentation.error_text"
    assert_includes web, "Master::CLI::TurnPresentation.text(result)"
  end

  def test_smoke_turns_have_one_router_owner
    router = read("lib/cli/turn_router.rb")
    controller = read("web/app/controllers/chat_controller.rb")
    service = read("web/app/services/chat_service.rb")

    assert_includes router, "SMOKE_RESPONSES"
    refute_match(/smoke_chat_message\?|stream_smoke_reply/, controller)
    refute_match(/SMOKE_MESSAGES|def smoke_reply\?|def smoke_response/, service)
  end

  def test_command_surface_is_derived_from_the_real_slash_surface
    surface = Master::CLI::CommandRegistry.command_surface
    assert_equal Master::CLI::CommandRegistry.slash_commands.sort, surface.map { |row| row.fetch(:cmd) }.sort
  end
end
