# frozen_string_literal: true

require "test_helper"

# Consequential tools reach the world under a receipt: lib/builder.rb builds them
# for the tool dispatcher and MCP, which wrap every call in Trace::ToolObserver,
# and the Fold's effects pass Trace::EffectObserver. A tool built anywhere else
# is a route around both, so each such site is named here with what audits it.
# A new one fails this test until it is given a receipt and a line below.
class TestEffectBoundaryInventory < Minitest::Test
  TOOLS = %w[WriteFile Shell DeletePath StrReplace BatchReplace AstEdit GitOperations GithubOperations Gist
             WebFetch WebBrowse BrowserAgent CodePen Clean ExternalAudit Nmap Relayd ProcessSpawn
             ScriptDispatch DynamicHttp].freeze
  BUILT = /Io::(#{TOOLS.join('|')})\.new/

  AUDITED_ELSEWHERE = {
    # GitOperations#git! writes a ToolObserver receipt for every add, commit, push and rebase.
    "lib/builder/ai_boot.rb" => "GitOperations",
    "lib/cli/command_registry.rb" => "GitOperations",
    "lib/cli/command_registry/status.rb" => "GitOperations",
    "lib/cli/pipeline/pass.rb" => "GitOperations",
    "lib/cli/pipeline/proof.rb" => "GitOperations",
    "lib/fix/file_rename.rb" => "GitOperations",
    "lib/fix/fix_loop.rb" => "GitOperations",
    "lib/fix/fix_loop/repo_scope.rb" => "GitOperations",
    "lib/fix/restructure.rb" => "GitOperations",
    "lib/fix/wishlist.rb" => "GitOperations",
    # The Fold's fetch: CoreBridge runs it inside an effect the EffectObserver brackets.
    "lib/cli/core_bridge.rb" => "WebFetch",
    # `!command` in the REPL: the operator typing a shell line; Shell asks its governor.
    "lib/cli/session/repl_flow.rb" => "Shell",
  }.freeze

  def built_outside_the_builder
    root = Master::ROOT
    Dir.glob(File.join(root, "lib", "**", "*.rb")).sort.each_with_object({}) do |path, sites|
      relative = path.delete_prefix("#{root}/")
      next if relative == "lib/builder.rb" || relative.start_with?("lib/io/")

      tools = File.read(path).scan(BUILT).flatten.uniq
      sites[relative] = tools.sort.join(",") unless tools.empty?
    end
  end

  def test_every_consequential_tool_built_outside_the_builder_is_accounted_for
    assert_equal AUDITED_ELSEWHERE.sort.to_h, built_outside_the_builder
  end
end
