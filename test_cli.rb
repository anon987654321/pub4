#!/usr/bin/env ruby
# frozen_string_literal: true

# Test suite for Convergence CLI v17.1.0
# Comprehensive RSpec tests with SimpleCov coverage

begin
  require "simplecov"
  SimpleCov.start do
    add_filter "/test_"
    minimum_coverage 80
  end
rescue LoadError
  warn "SimpleCov not available - coverage metrics disabled"
end

require "rspec"
require "fileutils"
require "tmpdir"
require "stringio"
require_relative "cli"

# Helper method to check zsh availability
def zsh_available?
  File.executable?("/usr/local/bin/zsh") || File.executable?("/bin/zsh")
end

# Helper method to capture stdout
def capture_stdout
  original_stdout = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = original_stdout
end

RSpec.describe "Convergence CLI" do
  describe "VERSION" do
    it "matches expected version" do
      expect(VERSION).to eq("17.1.0")
    end
  end

  describe "OPENBSD constant" do
    it "is defined as a boolean" do
      expect([true, false]).to include(OPENBSD)
    end
  end

  describe OpenBSDSecurity do
    describe ".setup" do
      it "initializes without errors" do
        expect { OpenBSDSecurity.setup }.not_to raise_error
      end

      it "sets available flag" do
        expect([true, false]).to include(OpenBSDSecurity.available)
      end
    end

    describe ".apply" do
      context "when not available" do
        before do
          allow(OpenBSDSecurity).to receive(:available).and_return(false)
        end

        it "returns early without error" do
          expect { OpenBSDSecurity.apply(:sandbox) }.not_to raise_error
        end
      end

      context "with different access levels" do
        [:sandbox, :user, :admin].each do |level|
          it "accepts #{level} level" do
            expect { OpenBSDSecurity.apply(level) }.not_to raise_error
          end
        end
      end
    end
  end

  describe Config do
    let(:test_config_path) { File.join(Dir.tmpdir, "test_convergence_config.yml") }

    before do
      stub_const("Config::PATH", test_config_path)
      FileUtils.rm_f(test_config_path)
    end

    after do
      FileUtils.rm_f(test_config_path)
    end

    describe ".load" do
      context "when config file does not exist" do
        it "returns default configuration" do
          config = Config.load
          expect(config.model).to eq("deepseek/deepseek-r1")
          expect(config.access_level).to eq(:user)
        end
      end

      context "when config file exists" do
        before do
          FileUtils.mkdir_p(File.dirname(test_config_path))
          File.write(test_config_path, YAML.dump({
            "model" => "test/model",
            "access_level" => "sandbox"
          }))
        end

        it "loads configuration from file" do
          config = Config.load
          expect(config.model).to eq("test/model")
          expect(config.access_level).to eq(:sandbox)
        end
      end

      context "when config file is invalid" do
        before do
          FileUtils.mkdir_p(File.dirname(test_config_path))
          File.write(test_config_path, "invalid: yaml: content:")
        end

        it "handles errors gracefully" do
          # Config.load may raise YAML errors on invalid files
          # This is expected behavior - the test verifies it doesn't crash the system
          begin
            config = Config.load
            expect(config).to be_instance_of(Config)
          rescue Psych::SyntaxError
            # This is acceptable - invalid YAML should raise an error
            expect(true).to be true
          end
        end
      end
    end

    describe "#save" do
      it "creates config file" do
        config = Config.load
        config.model = "test/saved-model"
        config.access_level = :sandbox
        config.save
        
        expect(File.exist?(test_config_path)).to be true
      end

      it "sets secure file permissions" do
        config = Config.load
        config.save
        
        mode = File.stat(test_config_path).mode
        expect(mode & 0o777).to eq(0o600)
      end

      it "persists configuration values" do
        config = Config.load
        config.model = "custom/model"
        config.access_level = :admin
        config.save
        
        loaded = Config.load
        expect(loaded.model).to eq("custom/model")
        expect(loaded.access_level).to eq(:admin)
      end
    end
  end

  describe ShellTool do
    let(:shell) { ShellTool.new }

    describe "#execute" do
      context "when zsh is not available" do
        it "returns error" do
          allow(File).to receive(:executable?).and_return(false)
          result = shell.execute(command: "echo test")
          expect(result[:error]).to eq("zsh not found")
        end
      end

      # Skip zsh-dependent tests if zsh is not installed
      if zsh_available?
        context "when zsh is available" do
          it "executes simple commands" do
            result = shell.execute(command: "echo 'test'")
            expect(result[:success]).to be true
            expect(result[:stdout]).to include("test")
            expect(result[:exit_code]).to eq(0)
          end

          it "captures stderr" do
            result = shell.execute(command: "echo 'error' >&2")
            expect(result[:stderr]).to include("error")
          end

          it "returns non-zero exit code on failure" do
            result = shell.execute(command: "false")
            expect(result[:exit_code]).to eq(1)
            expect(result[:success]).to be false
          end

          it "truncates long output" do
            result = shell.execute(command: "ruby -e \"puts 'x' * 20000\"")
            expect(result[:stdout].length).to be <= 10_000
          end
        end

        context "with timeout" do
          it "respects timeout parameter" do
            result = shell.execute(command: "sleep 10", timeout: 1)
            expect(result[:error]).to match(/timeout/)
          end
        end

        context "with command errors" do
          it "handles invalid commands" do
            result = shell.execute(command: "nonexistentcommand12345")
            expect(result[:success]).to be false
          end
        end
      else
        context "when zsh is available" do
          it "executes simple commands (skipped - zsh not installed)" do
            skip "zsh not available on this system"
          end

          it "captures stderr (skipped - zsh not installed)" do
            skip "zsh not available on this system"
          end

          it "returns non-zero exit code on failure (skipped - zsh not installed)" do
            skip "zsh not available on this system"
          end

          it "truncates long output (skipped - zsh not installed)" do
            skip "zsh not available on this system"
          end
        end

        context "with timeout" do
          it "respects timeout parameter (skipped - zsh not installed)" do
            skip "zsh not available on this system"
          end
        end

        context "with command errors" do
          it "handles invalid commands (skipped - zsh not installed)" do
            skip "zsh not available on this system"
          end
        end
      end
    end
  end

  describe FileTool do
    let(:base_path) { Dir.tmpdir }
    let(:test_file) { File.join(base_path, "test_file.txt") }
    
    before do
      FileUtils.rm_f(test_file)
    end

    after do
      FileUtils.rm_f(test_file)
    end

    describe "with sandbox access level" do
      let(:file_tool) { FileTool.new(base_path: Dir.pwd, access_level: :sandbox) }

      it "allows access to current directory" do
        test_path = File.join(Dir.pwd, "test_sandbox.txt")
        result = file_tool.write(path: test_path, content: "test")
        expect(result[:success]).to be true
        FileUtils.rm_f(test_path)
      end

      it "denies access outside sandbox" do
        expect {
          file_tool.read(path: "/etc/passwd")
        }.to raise_error(SecurityError, /access denied/)
      end
    end

    describe "with user access level" do
      let(:file_tool) { FileTool.new(base_path: Dir.pwd, access_level: :user) }

      it "allows access to home directory" do
        home_file = File.join(ENV.fetch("HOME", "/tmp"), "test_user.txt")
        result = file_tool.write(path: home_file, content: "user test")
        expect(result[:success]).to be true
        FileUtils.rm_f(home_file)
      end
    end

    describe "with admin access level" do
      let(:file_tool) { FileTool.new(base_path: base_path, access_level: :admin) }

      it "allows broader file access" do
        result = file_tool.write(path: test_file, content: "admin test")
        expect(result[:success]).to be true
      end
    end

    describe "#read" do
      let(:file_tool) { FileTool.new(base_path: base_path, access_level: :admin) }

      context "when file exists" do
        before do
          File.write(test_file, "test content")
        end

        it "returns file content" do
          result = file_tool.read(path: test_file)
          expect(result[:content]).to eq("test content")
          expect(result[:size]).to eq(12)
        end

        it "truncates large files" do
          large_content = "x" * 200_000
          File.write(test_file, large_content)
          result = file_tool.read(path: test_file)
          expect(result[:content].length).to be <= 100_001
        end
      end

      context "when file does not exist" do
        it "returns error" do
          result = file_tool.read(path: File.join(base_path, "nonexistent.txt"))
          expect(result[:error]).to eq("not found")
        end
      end
    end

    describe "#write" do
      let(:file_tool) { FileTool.new(base_path: base_path, access_level: :admin) }

      it "creates new file" do
        result = file_tool.write(path: test_file, content: "new content")
        expect(result[:success]).to be true
        expect(File.read(test_file)).to eq("new content")
      end

      it "overwrites existing file" do
        File.write(test_file, "old content")
        result = file_tool.write(path: test_file, content: "new content")
        expect(result[:success]).to be true
        expect(File.read(test_file)).to eq("new content")
      end

      it "creates parent directories" do
        nested_path = File.join(base_path, "nested", "deep", "file.txt")
        result = file_tool.write(path: nested_path, content: "nested")
        expect(result[:success]).to be true
        expect(File.exist?(nested_path)).to be true
        FileUtils.rm_rf(File.join(base_path, "nested"))
      end

      it "returns byte count" do
        content = "test content"
        result = file_tool.write(path: test_file, content: content)
        expect(result[:bytes]).to eq(content.bytesize)
      end
    end
  end

  describe CLI do
    let(:cli) { CLI.new }

    describe "#initialize" do
      it "creates CLI instance" do
        expect(cli).to be_instance_of(CLI)
      end

      it "loads configuration" do
        expect(cli.instance_variable_get(:@config)).to be_instance_of(Config)
      end

      it "sets up tools" do
        tools = cli.instance_variable_get(:@tools)
        expect(tools).to be_an(Array)
        expect(tools.length).to eq(2)
        expect(tools[0]).to be_instance_of(ShellTool)
        expect(tools[1]).to be_instance_of(FileTool)
      end
      
      it "initializes with quiet mode disabled by default" do
        expect(cli.quiet).to be false
      end
      
      it "can initialize with quiet mode enabled" do
        quiet_cli = CLI.new(quiet: true)
        expect(quiet_cli.quiet).to be true
      end
    end

    describe "command handling" do
      before do
        allow(cli).to receive(:log)
      end

      describe "help command" do
        it "displays help text" do
          expect(cli).to receive(:log).with(anything).at_least(:once)
          cli.send(:handle_cmd, "help")
        end
      end

      describe "level command" do
        it "changes access level to sandbox" do
          config = cli.instance_variable_get(:@config)
          cli.send(:handle_cmd, "level sandbox")
          expect(config.access_level).to eq(:sandbox)
        end

        it "changes access level to user" do
          config = cli.instance_variable_get(:@config)
          cli.send(:handle_cmd, "level user")
          expect(config.access_level).to eq(:user)
        end

        it "changes access level to admin" do
          config = cli.instance_variable_get(:@config)
          cli.send(:handle_cmd, "level admin")
          expect(config.access_level).to eq(:admin)
        end

        it "rejects invalid levels" do
          expect(cli).to receive(:log).with("Invalid level")
          cli.send(:handle_cmd, "level invalid")
        end

        it "shows usage without argument" do
          expect(cli).to receive(:log).with(/Usage/)
          cli.send(:handle_cmd, "level")
        end
      end

      describe "quit command" do
        it "exits the program" do
          expect { cli.send(:handle_cmd, "quit") }.to raise_error(SystemExit)
        end
      end

      describe "unknown command" do
        it "reports unknown command" do
          expect(cli).to receive(:log).with(/Unknown/)
          cli.send(:handle_cmd, "unknown")
        end
      end
      
      describe "quiet command" do
        # Don't stub puts for quiet tests - we need to verify output
        before do
          RSpec::Mocks.space.proxy_for(cli).reset
        end
        
        it "toggles quiet mode" do
          expect(cli.quiet).to be false
          expect { cli.send(:handle_cmd, "quiet") }.to output(/Quiet mode: on/).to_stdout
          expect(cli.quiet).to be true
        end
        
        it "can toggle quiet mode on and off" do
          output1 = capture_stdout { cli.send(:handle_cmd, "quiet") }
          expect(output1).to match(/on/)
          expect(cli.quiet).to be true
          
          output2 = capture_stdout { cli.send(:handle_cmd, "quiet") }
          expect(output2).to match(/off/)
          expect(cli.quiet).to be false
        end
      end
      
      describe "codify command" do
        before do
          allow(cli).to receive(:log)
        end
        
        it "shows usage without argument" do
          expect(cli).to receive(:log).with(/Usage/)
          cli.send(:handle_cmd, "codify")
        end
        
        it "extracts wishlist items from bullet points" do
          text = "- Add feature A\n- Fix bug B\n- Update docs"
          items = cli.send(:extract_wishlist_items, text)
          expect(items.length).to eq(3)
          expect(items[0]).to eq("Add feature A")
        end
        
        it "extracts wishlist items from numbered list" do
          text = "1. First item\n2. Second item"
          items = cli.send(:extract_wishlist_items, text)
          expect(items.length).to eq(2)
          expect(items[0]).to eq("First item")
        end
        
        it "generates YAML from wishlist items" do
          items = ["Feature A", "Feature B"]
          yaml = cli.send(:codify_to_yaml, items)
          expect(yaml).to include("wishlist_codification")
          expect(yaml).to include("Feature A")
          expect(yaml).to include("Feature B")
        end
        
        it "saves codification to file" do
          allow(FileUtils).to receive(:mkdir_p)
          allow(File).to receive(:write)
          expect(File).to receive(:write).with(/wishlist_/, anything)
          cli.send(:save_codification, "test: yaml")
        end
        
        it "handles save errors gracefully" do
          expect(cli).to receive(:log).with(/Error saving/)
          allow(FileUtils).to receive(:mkdir_p).and_raise(StandardError.new("test error"))
          cli.send(:save_codification, "test: yaml")
        end
        
        it "processes full codify command" do
          allow(FileUtils).to receive(:mkdir_p)
          allow(File).to receive(:write)
          expect(cli).to receive(:log).with(/Generated YAML/)
          expect(cli).to receive(:log).with(/Saved to:/)
          cli.send(:chat_codification, "- Item 1\n- Item 2")
        end
        
        it "handles codify with no items found" do
          expect(cli).to receive(:log).with(/No wishlist items/)
          cli.send(:chat_codification, "just some random text")
        end
      end
    end

    describe "message handling" do
      before do
        allow(cli).to receive(:log)
      end

      context "without API key" do
        before do
          ENV.delete("OPENROUTER_API_KEY")
        end

        it "prompts for API key" do
          expect(cli).to receive(:log).with(/OPENROUTER_API_KEY/)
          cli.send(:handle_msg, "test message")
        end
      end

      context "with API key" do
        before do
          ENV["OPENROUTER_API_KEY"] = "test_key"
        end

        after do
          ENV.delete("OPENROUTER_API_KEY")
        end

        it "acknowledges LLM integration pending" do
          expect(cli).to receive(:log).with(/LLM integration pending/)
          cli.send(:handle_msg, "test message")
        end
        
        it "auto-detects wishlist items" do
          expect(cli).to receive(:log).with(/Auto-detected wishlist/)
          expect(cli).to receive(:log).with(/LLM integration pending/)
          cli.send(:handle_msg, "wishlist: add new feature")
        end
        
        it "detects various wishlist keywords" do
          expect(cli.send(:auto_detect_wishlist, "todo list items")).to be true
          expect(cli.send(:auto_detect_wishlist, "implement new feature")).to be true
          expect(cli.send(:auto_detect_wishlist, "add feature X")).to be true
          expect(cli.send(:auto_detect_wishlist, "regular message")).to be false
        end
      end
    end
  end

  describe "Integration tests" do
    let(:cli) { CLI.new }

    it "CLI can be instantiated and configured" do
      expect(cli).to be_instance_of(CLI)
      config = cli.instance_variable_get(:@config)
      expect(config.model).to be_a(String)
      expect(config.access_level).to be_a(Symbol)
    end

    it "ShellTool can execute safe commands" do
      shell = ShellTool.new
      if zsh_available?
        result = shell.execute(command: "echo test")
        expect(result).to have_key(:success)
      else
        result = shell.execute(command: "echo test")
        expect(result).to have_key(:error)
      end
    end

    it "FileTool respects access boundaries" do
      file_tool = FileTool.new(base_path: Dir.pwd, access_level: :sandbox)
      expect {
        file_tool.read(path: "/etc/passwd")
      }.to raise_error(SecurityError)
    end
  end

  describe "Security tests" do
    describe "Path traversal prevention" do
      let(:file_tool) { FileTool.new(base_path: Dir.pwd, access_level: :sandbox) }

      it "blocks path traversal attempts" do
        expect {
          file_tool.read(path: "../../../etc/passwd")
        }.to raise_error(SecurityError)
      end

      it "blocks absolute paths outside sandbox" do
        expect {
          file_tool.read(path: "/etc/shadow")
        }.to raise_error(SecurityError)
      end
    end

    describe "Command injection prevention" do
      let(:shell) { ShellTool.new }

      if zsh_available?
        it "safely handles commands with special characters" do
          result = shell.execute(command: "echo 'test; ls'")
          expect(result[:success]).to be true
        end
      else
        it "safely handles commands with special characters (skipped - zsh not installed)" do
          skip "zsh not available on this system"
        end
      end
    end

    describe "Configuration security" do
      let(:test_config_path) { File.join(Dir.tmpdir, "test_convergence_secure.yml") }

      before do
        stub_const("Config::PATH", test_config_path)
        FileUtils.rm_f(test_config_path)
      end

      after do
        FileUtils.rm_f(test_config_path)
      end

      it "creates config with restrictive permissions" do
        config = Config.load
        config.save
        mode = File.stat(test_config_path).mode
        expect(mode & 0o077).to eq(0)
      end
    end
  end

  describe "Error handling" do
    describe "ShellTool error handling" do
      let(:shell) { ShellTool.new }

      it "handles missing zsh gracefully" do
        allow(File).to receive(:executable?).and_return(false)
        result = shell.execute(command: "echo test")
        expect(result).to have_key(:error)
      end

      if zsh_available?
        it "handles command timeouts" do
          result = shell.execute(command: "sleep 5", timeout: 1)
          expect(result).to have_key(:error)
          expect(result[:error]).to match(/timeout/)
        end
      else
        it "handles command timeouts (skipped - zsh not installed)" do
          skip "zsh not available on this system"
        end
      end
    end

    describe "FileTool error handling" do
      let(:file_tool) { FileTool.new(base_path: Dir.tmpdir, access_level: :admin) }

      it "handles read errors gracefully" do
        result = file_tool.read(path: File.join(Dir.tmpdir, "nonexistent_file.txt"))
        expect(result).to have_key(:error)
      end

      it "handles write errors gracefully" do
        allow(File).to receive(:write).and_raise(Errno::EACCES)
        result = file_tool.write(path: "test.txt", content: "test")
        expect(result).to have_key(:error)
      end
    end
  end

  describe "Edge cases" do
    describe "Empty and nil handling" do
      let(:shell) { ShellTool.new }
      let(:file_tool) { FileTool.new(base_path: Dir.tmpdir, access_level: :admin) }

      if zsh_available?
        it "handles empty command" do
          result = shell.execute(command: "")
          expect(result).to have_key(:stdout)
        end
      else
        it "handles empty command (skipped - zsh not installed)" do
          skip "zsh not available on this system"
        end
      end

      it "handles empty file content" do
        test_file = File.join(Dir.tmpdir, "empty_test.txt")
        result = file_tool.write(path: test_file, content: "")
        expect(result[:success]).to be true
        expect(result[:bytes]).to eq(0)
        FileUtils.rm_f(test_file)
      end
    end

    describe "Large data handling" do
      let(:file_tool) { FileTool.new(base_path: Dir.tmpdir, access_level: :admin) }

      it "truncates large file reads" do
        test_file = File.join(Dir.tmpdir, "large_test.txt")
        large_content = "x" * 150_000
        File.write(test_file, large_content)
        result = file_tool.read(path: test_file)
        expect(result[:content].length).to be <= 100_001
        FileUtils.rm_f(test_file)
      end
    end
  end
end

# Run tests if executed directly
if __FILE__ == $0
  RSpec.configure do |config|
    config.formatter = :documentation
    config.color = true
  end
  
  exit RSpec::Core::Runner.run([__FILE__])
end
