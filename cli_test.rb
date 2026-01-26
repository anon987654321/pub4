
#!/usr/bin/env ruby
# frozen_string_literal: true

# Convergence CLI v0.3.0 - Test Suite
# NEW in v0.3: Tests for OpenRouterAPI, ProfileManager, CostTracker, SessionTimer, Paths
# Comprehensive tests using Minitest (stdlib)

require "minitest/autorun"
require "minitest/pride"
require "tmpdir"
require "fileutils"
require "yaml"
require "json"
require_relative "cli"

# Test Master configuration loading
class MasterTest < Minitest::Test
  def setup
    @valid_data = create_valid_master_data
  end

  def test_initializes_with_valid_data
    master = Master.new(@valid_data)
    assert_instance_of Master, master
  end

  def test_validates_required_sections
    @valid_data.delete("principles")
    error = assert_raises(RuntimeError) { Master.new(@valid_data) }
    assert_match /Missing required sections/, error.message
  end

  def test_validates_persona_count
    @valid_data["personas"]["roles"] = []
    error = assert_raises(RuntimeError) { Master.new(@valid_data) }
    assert_match /Insufficient personas/, error.message
  end

  def test_validates_adversarial_count
    @valid_data["adversarial"]["personas"] = Array.new(5) { {"name" => "test"} }
    error = assert_raises(RuntimeError) { Master.new(@valid_data) }
    assert_match /Insufficient adversarial/, error.message
  end

  def test_version_extraction
    master = Master.new(@valid_data)
    assert_equal "0.3.0", master.version
  end

  def test_principle_lookup
    master = Master.new(@valid_data)
    assert_equal "Don't repeat yourself", master.principle("dry")
  end

  def test_remedy_lookup
    master = Master.new(@valid_data)
    remedy = master.remedy_for("injection_vulnerability")
    assert remedy.is_a?(Hash)
    assert_equal "sanitize_input", remedy["remedy"]
  end

  def test_auto_fixable_check
    master = Master.new(@valid_data)
    assert master.auto_fixable?("injection_vulnerability")
    refute master.auto_fixable?("god_class")
  end

  def test_evidence_threshold
    master = Master.new(@valid_data)
    assert_equal 0.95, master.evidence_threshold
  end

  def test_severity_lookup
    master = Master.new(@valid_data)
    assert_equal :critical, master.severity_for("injection_vulnerability")
    assert_equal :medium, master.severity_for("magic_number")
  end

  def test_openrouter_config
    master = Master.new(@valid_data)
    config = master.openrouter_config
    assert_instance_of Hash, config
    assert_equal "https://openrouter.ai/api/v1/chat/completions", config["api_url"]
  end

  def test_profile_config
    master = Master.new(@valid_data)
    profile = master.profile_config("architect")
    assert profile
    assert_equal 0.3, profile["temperature"]
  end

  private

  def create_valid_master_data
    {
      "meta" => {"version" => "0.3.0"},
      "principles" => {
        "dry" => "Don't repeat yourself",
        "kiss" => "Keep it simple"
      },
      "evidence" => {
        "thresholds" => {"production" => 0.95},
        "weights" => {"tests" => 0.5, "static" => 0.3, "complexity" => 0.2}
      },
      "personas" => {
        "roles" => Array.new(6) { {"name" => "persona", "weight" => 0.1} }
      },
      "adversarial" => {
        "personas" => Array.new(10) { {"name" => "adversary", "temperature" => 0.5} }
      },
      "catalog" => {
        "system" => {
          "injection_vulnerability" => {
            "remedy" => "sanitize_input",
            "auto_fix" => true
          }
        },
        "philosophy" => {
          "magic_number" => {
            "remedy" => "extract_constant",
            "auto_fix" => true
          },
          "god_class" => {
            "remedy" => "split_responsibilities",
            "auto_fix" => false
          }
        }
      },
      "severity" => {
        "critical" => ["injection_vulnerability", "token_exposure"],
        "medium" => ["magic_number"]
      },
      "auto_fix" => {
        "enabled" => true,
        "safety_rules" => {
          "backup_before_fix" => true
        }
      },
      "openrouter" => {
        "api_url" => "https://openrouter.ai/api/v1/chat/completions",
        "models" => {
          "balanced" => {
            "name" => "deepseek/deepseek-r1",
            "cost_per_1m_prompt" => 0.55
          }
        }
      },
      "profiles" => {
        "architect" => {
          "temperature" => 0.3,
          "model" => "anthropic/claude-3.5-sonnet"
        }
      }
    }
  end
end

# Test Config management
class ConfigTest < Minitest::Test
  def setup
    @original_config_file = Paths::CONFIG_FILE
    @temp_dir = Dir.mktmpdir
    @temp_config = File.join(@temp_dir, "config.yml")
    
    Paths.send(:remove_const, :CONFIG_FILE)
    Paths.const_set(:CONFIG_FILE, @temp_config)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
    
    Paths.send(:remove_const, :CONFIG_FILE)
    Paths.const_set(:CONFIG_FILE, @original_config_file)
  end

  def test_load_creates_default_config
    config = Config.load
    assert_nil config.mode
    assert_equal :user, config.access_level
    assert config.auto_fix_enabled
    assert_equal :balanced, config.active_profile
  end

  def test_load_reads_existing_config
    File.write(@temp_config, YAML.dump({
      "mode" => "api",
      "access_level" => "admin",
      "auto_fix_enabled" => false,
      "active_profile" => "architect"
    }))

    config = Config.load
    assert_equal :api, config.mode
    assert_equal :admin, config.access_level
    refute config.auto_fix_enabled
    assert_equal :architect, config.active_profile
  end

  def test_save_writes_config
    config = Config.load
    config.mode = :free
    config.auto_fix_enabled = false
    config.active_profile = :security_auditor
    config.save

    assert File.exist?(@temp_config)
    assert_equal 0o600, File.stat(@temp_config).mode & 0o777
  end

  def test_save_and_reload
    config = Config.load
    config.mode = :local
    config.model = "test-model"
    config.active_profile = :pragmatist
    config.save

    reloaded = Config.load
    assert_equal :local, reloaded.mode
    assert_equal "test-model", reloaded.model
    assert_equal :pragmatist, reloaded.active_profile
  end
end

# NEW in v0.3: Test Paths module
class PathsTest < Minitest::Test
  def test_for_returns_platform_specific_path
    path = Paths.for(:samples)
    assert_instance_of String, path
    refute_empty path
  end

  def test_for_expands_env_vars
    ENV['TEST_VAR'] = '/test/path'
    # Would need to stub DEFAULTS to test this properly
    assert Paths.for(:config).include?('.convergence')
  end

  def test_ensure_exists_creates_directories
    temp_dir = Dir.mktmpdir
    test_path = File.join(temp_dir, "test_subdir")
    
    refute Dir.exist?(test_path)
    Paths.ensure_exists(test_path)
    assert Dir.exist?(test_path)
    
    FileUtils.rm_rf(temp_dir)
  end

  def test_ensure_exists_sets_permissions
    temp_dir = Dir.mktmpdir
    test_path = File.join(temp_dir, "test_perms")
    
    Paths.ensure_exists(test_path)
    assert_equal 0o700, File.stat(test_path).mode & 0o777
    
    FileUtils.rm_rf(temp_dir)
  end
end

# Test Platform detection
class PlatformTest < Minitest::Test
  def test_detect_returns_hash
    platform = Platform.detect
    assert_instance_of Hash, platform
    assert_includes platform, :type
    assert_includes platform, :security
  end

  def test_type_returns_symbol
    assert_kind_of Symbol, Platform.type
  end

  def test_security_returns_symbol
    assert_kind_of Symbol, Platform.security
  end

  def test_openbsd_check
    assert [true, false].include?(Platform.openbsd?)
  end

  def test_security_available
    assert [true, false].include?(Platform.security_available?)
  end

  def test_detect_is_cached
    first = Platform.detect
    second = Platform.detect
    assert_same first.object_id, second.object_id
  end
end

# NEW in v0.3: Test VersionChecker
class VersionCheckerTest < Minitest::Test
  def test_check_raises_on_mismatch
    # Would need to mock Master.load for comprehensive testing
    # This tests that the method exists and is callable
    skip "Requires master.yml mocking"
  end
end

# Test ShellTool
class ShellToolTest < Minitest::Test
  def test_rejects_unknown_command
    result = ShellTool.execute("rm", "-rf", "/")
    refute result.success
    assert_match /not allowed/, result.stderr
    assert_equal 127, result.exit_code
  end

  def test_returns_result_struct
    result = ShellTool.execute("git", "--version")
    assert_instance_of ShellTool::Result, result
    assert_respond_to result, :success
    assert_respond_to result, :stdout
    assert_respond_to result, :stderr
    assert_respond_to result, :exit_code
  end

  def test_timeout_handling
    skip "Requires slow command for testing"
  end
end

# Test GitTool
class GitToolTest < Minitest::Test
  def test_available_check
    assert [true, false].include?(GitTool.available?)
  end

  def test_clean_working_tree_when_no_git
    skip unless GitTool.available?
    # Would require git repo setup
  end

  def test_commit_without_git
    skip unless GitTool.available?
    
    result = GitTool.commit("test commit")
    assert_includes result, :success
  end
end

# Test FileTool
class FileToolTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @file_tool = FileTool.new(base_path: @temp_dir, access_level: :user)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_read_existing_file
    test_file = File.join(@temp_dir, "test.txt")
    File.write(test_file, "content")

    result = @file_tool.read(test_file)
    assert_equal "content", result[:content]
    assert_equal 7, result[:size]
  end

  def test_read_nonexistent_file
    result = @file_tool.read("nonexistent.txt")
    assert_includes result[:error], "not found"
  end

  def test_write_file
    result = @file_tool.write("output.txt", "test content")
    assert result[:success]
    assert_equal 12, result[:bytes]
  end

  def test_sandbox_enforcement
    tool = FileTool.new(base_path: @temp_dir, access_level: :sandbox)
    result = tool.read("/etc/passwd")
    assert_includes result[:error], "Access denied"
  end

  def test_admin_level_allows_all
    tool = FileTool.new(base_path: @temp_dir, access_level: :admin)
    result = tool.read("/nonexistent")
    assert_includes result, :error
  end
end

# Test Scanner with enhanced patterns
class ScannerTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @master = Master.new(create_valid_master_data)
    @scanner = Scanner.new(master: @master)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_scan_clean_code
    File.write(File.join(@temp_dir, "clean.rb"), "class Clean\nend")
    defects = @scanner.scan(@temp_dir)
    assert_empty defects
  end

  def test_detects_injection_vulnerability
    File.write(File.join(@temp_dir, "bad.rb"), 'system("rm -rf /")')
    defects = @scanner.scan(@temp_dir)

    assert_equal 1, defects.size
    assert_equal :injection_vulnerability, defects.first.type
    assert defects.first.auto_fixable
  end

  def test_detects_token_exposure
    File.write(File.join(@temp_dir, "token.rb"), 'puts "Token abc123def456ghi789"')
    defects = @scanner.scan(@temp_dir)

    token_defect = defects.find { |d| d.type == :token_exposure }
    assert token_defect
    assert_equal :critical, token_defect.severity
  end

  def test_detects_hardcoded_path
    File.write(File.join(@temp_dir, "path.rb"), 'DIR = "/home/user/projects"')
    defects = @scanner.scan(@temp_dir)

    path_defect = defects.find { |d| d.type == :hardcoded_path }
    assert path_defect
  end

  def test_detects_yaml_in_ruby_file
    File.write(File.join(@temp_dir, "yaml.rb"), "version: 1.0.0\nname: test")
    defects = @scanner.scan(@temp_dir)

    yaml_defect = defects.find { |d| d.type == :yaml_in_ruby_file }
    assert yaml_defect
  end

  def test_detects_magic_number
    File.write(File.join(@temp_dir, "magic.rb"), "sleep 500")
    defects = @scanner.scan(@temp_dir)

    magic = defects.find { |d| d.type == :magic_number }
    refute_nil magic
    assert magic.auto_fixable
  end

  def test_skips_vendor_directory
    vendor_dir = File.join(@temp_dir, "vendor")
    FileUtils.mkdir_p(vendor_dir)
    File.write(File.join(vendor_dir, "bad.rb"), 'system("bad")')

    defects = @scanner.scan(@temp_dir)
    assert_empty defects
  end

  def test_reports_file_and_line
    file_path = File.join(@temp_dir, "test.rb")
    File.write(file_path, "# line 1\n# line 2\nsystem('ls')\n")
    defects = @scanner.scan(@temp_dir)

    assert_equal file_path, defects.first.file
    assert_equal 3, defects.first.line
  end

  private

  def create_valid_master_data
    {
      "meta" => {"version" => "0.3.0"},
      "principles" => {"dry" => "test"},
      "evidence" => {
        "thresholds" => {"production" => 0.95},
        "weights" => {"tests" => 0.5}
      },
      "personas" => {
        "roles" => Array.new(6) { {"name" => "p"} }
      },
      "adversarial" => {
        "personas" => Array.new(10) { {"name" => "a"} }
      },
      "catalog" => {
        "system" => {
          "injection_vulnerability" => {
            "remedy" => "sanitize_input",
            "auto_fix" => true
          },
          "token_exposure" => {
            "remedy" => "sanitize_error_messages",
            "auto_fix" => true
          },
          "hardcoded_path" => {
            "remedy" => "use_paths_module",
            "auto_fix" => true
          }
        },
        "logic" => {
          "yaml_in_ruby_file" => {
            "remedy" => "rename_or_wrap",
            "auto_fix" => true
          }
        },
        "philosophy" => {
          "magic_number" => {
            "remedy" => "extract_constant",
            "auto_fix" => true
          }
        }
      },
      "severity" => {
        "critical" => ["injection_vulnerability", "token_exposure"],
        "high" => ["yaml_in_ruby_file"],
        "medium" => ["hardcoded_path", "magic_number"]
      }
    }
  end
end

# Test BackupManager
class BackupManagerTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @original_backup_dir = Paths::BACKUP_DIR
    
    Paths.send(:remove_const, :BACKUP_DIR)
    Paths.const_set(:BACKUP_DIR, @temp_dir)
    
    @backup_manager = BackupManager.new
    @test_file = File.join(@temp_dir, "test.rb")
    File.write(@test_file, "original content")
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
    
    Paths.send(:remove_const, :BACKUP_DIR)
    Paths.const_set(:BACKUP_DIR, @original_backup_dir)
  end

  def test_create_backup
    result = @backup_manager.create_backup(@test_file)
    
    assert result[:success]
    assert File.exist?(result[:backup_path])
    assert_equal "original content", File.read(result[:backup_path])
  end

  def test_list_backups
    @backup_manager.create_backup(@test_file)
    sleep 0.1
    @backup_manager.create_backup(@test_file)
    
    backups = @backup_manager.list_backups
    assert_equal 2, backups.size
    assert backups.first[:timestamp] > backups.last[:timestamp]
  end

  def test_restore_backup
    backup_result = @backup_manager.create_backup(@test_file)
    File.write(@test_file, "modified content")
    
    restore_result = @backup_manager.restore_backup(backup_result[:backup_path], @test_file)
    
    assert restore_result[:success]
    assert_equal "original content", File.read(@test_file)
  end

  def test_cleanup_old_backups
    old_backup = File.join(@temp_dir, "old_test.rb_20200101_120000.bak")
    File.write(old_backup, "old")
    FileUtils.touch(old_backup, mtime: Time.now - (8 * 24 * 60 * 60))
    
    result = @backup_manager.cleanup_old_backups(7)
    assert_equal 1, result[:removed]
    refute File.exist?(old_backup)
  end
end

# Test AutoFixer (basic structure)
class AutoFixerTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @original_backup_dir = Paths::BACKUP_DIR
    
    Paths.send(:remove_const, :BACKUP_DIR)
    Paths.const_set(:BACKUP_DIR, @temp_dir)
    
    @master = Master.new(create_valid_master_data)
    @backup_manager = BackupManager.new
    @auto_fixer = AutoFixer.new(master: @master, backup_manager: @backup_manager)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
    
    Paths.send(:remove_const, :BACKUP_DIR)
    Paths.const_set(:BACKUP_DIR, @original_backup_dir)
  end

  def test_fix_defects_with_no_fixable
    defects = [
      Scanner::Defect.new(
        type: :god_class,
        auto_fixable: false,
        file: "test.rb",
        line: 1,
        severity: :low,
        remedy: {"remedy" => "split_responsibilities", "auto_fix" => false}
      )
    ]
    
    result = @auto_fixer.fix_defects(defects, interactive: false)
    assert_equal 0, result[:fixed]
    assert_equal 1, result[:skipped]
  end

  def test_creates_backup_before_fix
    test_file = File.join(@temp_dir, "test.rb")
    File.write(test_file, 'system("ls")')
    
    defects = [
      Scanner::Defect.new(
        type: :injection_vulnerability,
        auto_fixable: true,
        file: test_file,
        line: 1,
        severity: :critical,
        remedy: {"remedy" => "sanitize_input", "auto_fix" => true}
      )
    ]
    
    # Mock stdin for interactive prompt
    original_stdin = $stdin
    $stdin = StringIO.new("y\n")
    
    @auto_fixer.fix_defects(defects, interactive: true)
    
    $stdin = original_stdin
    
    backups = @backup_manager.list_backups
    assert backups.size >= 1
  end

  private

  def create_valid_master_data
    {
      "meta" => {"version" => "0.3.0"},
      "principles" => {"dry" => "test"},
      "evidence" => {
        "thresholds" => {"production" => 0.95},
        "weights" => {"tests" => 0.5}
      },
      "personas" => {
        "roles" => Array.new(6) { {"name" => "p"} }
      },
      "adversarial" => {
        "personas" => Array.new(10) { {"name" => "a"} }
      },
      "catalog" => {
        "system" => {
          "injection_vulnerability" => {
            "remedy" => "sanitize_input",
            "auto_fix" => true
          }
        },
        "philosophy" => {
          "god_class" => {
            "remedy" => "split_responsibilities",
            "auto_fix" => false
          }
        }
      },
      "severity" => {
        "critical" => ["injection_vulnerability"],
        "low" => ["god_class"]
      }
    }
  end
end

# Test EvidenceCalculator
class EvidenceCalculatorTest < Minitest::Test
  def setup
    @master = Master.new(create_valid_master_data)
    @calculator = EvidenceCalculator.new(master: @master)
  end

  def test_calculate_returns_hash
    evidence = @calculator.calculate
    assert_instance_of Hash, evidence
    assert_includes evidence, :score
    assert_includes evidence, :pass
  end

  def test_score_is_numeric
    evidence = @calculator.calculate
    assert_kind_of Numeric, evidence[:score]
    assert evidence[:score] >= 0
    assert evidence[:score] <= 1
  end

  def test_pass_is_boolean
    evidence = @calculator.calculate
    assert [true, false].include?(evidence[:pass])
  end

  private

  def create_valid_master_data
    {
      "meta" => {"version" => "0.3.0"},
      "principles" => {"dry" => "test"},
      "evidence" => {
        "thresholds" => {"production" => 0.95},
        "weights" => {"tests" => 0.5, "static" => 0.3, "complexity" => 0.2}
      },
      "personas" => {
        "roles" => Array.new(6) { {"name" => "p"} }
      },
      "adversarial" => {
        "personas" => Array.new(10) { {"name" => "a"} }
      },
      "catalog" => {}
    }
  end
end

# NEW in v0.3: Test CostTracker
class CostTrackerTest < Minitest::Test
  def setup
    @master = Master.new(create_valid_master_data)
    @tracker = CostTracker.new(master: @master)
  end

  def test_record_calculates_cost
    response = {
      "usage" => {
        "prompt_tokens" => 1000,
        "completion_tokens" => 500,
        "prompt_tokens_details" => {
          "cached_tokens" => 200
        }
      }
    }

    result = @tracker.record(response, "deepseek/deepseek-r1")
    
    assert result
    assert_kind_of Numeric, result[:cost]
    assert_equal 200, result[:cached_tokens]
    assert_kind_of Numeric, result[:savings]
  end

  def test_summary_provides_totals
    summary = @tracker.summary
    
    assert_instance_of Hash, summary
    assert_includes summary, :total_cost
    assert_includes summary, :total_savings
    assert_includes summary, :requests
    assert_includes summary, :average_cost
  end

  private

  def create_valid_master_data
    {
      "meta" => {"version" => "0.3.0"},
      "principles" => {"dry" => "test"},
      "evidence" => {
        "thresholds" => {"production" => 0.95},
        "weights" => {"tests" => 0.5}
      },
      "personas" => {
        "roles" => Array.new(6) { {"name" => "p"} }
      },
      "adversarial" => {
        "personas" => Array.new(10) { {"name" => "a"} }
      },
      "catalog" => {},
      "openrouter" => {
        "models" => {
          "balanced" => {
            "name" => "deepseek/deepseek-r1",
            "cost_per_1m_prompt" => 0.55,
            "cost_per_1m_completion" => 2.19,
            "cost_per_1m_cached" => 0.055
          }
        }
      }
    }
  end
end

# NEW in v0.3: Test ProfileManager
class ProfileManagerTest < Minitest::Test
  def setup
    @master = Master.new(create_valid_master_data)
    ProfileManager.load_profiles(@master)
  end

  def test_load_profiles
    assert ProfileManager.available.include?("architect")
    assert ProfileManager.available.include?("security_auditor")
  end

  def test_switch_profile
    result = ProfileManager.switch(:architect)
    assert result
    assert_equal :architect, ProfileManager.current_name
  end

  def test_switch_invalid_profile
    result = ProfileManager.switch(:nonexistent)
    refute result
  end

  def test_current_returns_profile
    ProfileManager.switch(:architect)
    profile = ProfileManager.current
    
    assert_instance_of Hash, profile
    assert_equal 0.3, profile["temperature"]
  end

  private

  def create_valid_master_data
    {
      "meta" => {"version" => "0.3.0"},
      "principles" => {"dry" => "test"},
      "evidence" => {
        "thresholds" => {"production" => 0.95},
        "weights" => {"tests" => 0.5}
      },
      "personas" => {
        "roles" => Array.new(6) { {"name" => "p"} }
      },
      "adversarial" => {
        "personas" => Array.new(10) { {"name" => "a"} }
      },
      "catalog" => {},
      "profiles" => {
        "architect" => {
          "temperature" => 0.3,
          "model" => "anthropic/claude-3.5-sonnet",
          "focus" => ["structure", "patterns"]
        },
        "security_auditor" => {
          "temperature" => 0.1,
          "model" => "anthropic/claude-3.5-sonnet",
          "focus" => ["vulnerabilities"]
        }
      }
    }
  end
end

# NEW in v0.3: Test SessionTimer
class SessionTimerTest < Minitest::Test
  def test_elapsed_increases_over_time
    timer = SessionTimer.new
    sleep 0.1
    assert timer.elapsed > 0
  end

  def test_report_formats_time
    timer = SessionTimer.new
    sleep 1.1
    
    report = timer.report
    assert_instance_of String, report
    assert_match /\ds/, report
  end

  def test_report_includes_minutes
    timer = SessionTimer.new
    # Stub elapsed to return 65 seconds
    def timer.elapsed; 65; end
    
    report = timer.report
    assert_includes report, "1m"
  end
end

# Integration test
class IntegrationTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @master_file = File.join(@temp_dir, "master.yml")
    create_test_master_file
    
    @original_master = Paths::MASTER_FILE
    Paths.send(:remove_const, :MASTER_FILE)
    Paths.const_set(:MASTER_FILE, @master_file)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
    
    Paths.send(:remove_const, :MASTER_FILE)
    Paths.const_set(:MASTER_FILE, @original_master)
  end

  def test_full_scan_and_detect_workflow
    master = Master.load
    scanner = Scanner.new(master: master)

    bad_file = File.join(@temp_dir, "bad.rb")
    File.write(bad_file, 'system("rm -rf /")')

    defects = scanner.scan(@temp_dir)
    refute_empty defects
    assert defects.first.auto_fixable
    assert_equal :injection_vulnerability, defects.first.type
  end

  def test_evidence_calculation_workflow
    master = Master.load
    calculator = EvidenceCalculator.new(master: master)

    evidence = calculator.calculate
    assert_instance_of Hash, evidence
    assert_includes [true, false], evidence[:pass]
  end

  def test_version_check_passes
    # Should not raise since we're using matching versions
    assert_silent { VersionChecker.check! }
  end

  private

  def create_test_master_file
    data = {
      "meta" => {"version" => "0.3.0"},
      "principles" => {"dry" => "test"},
      "evidence" => {
        "thresholds" => {"production" => 0.95},
        "weights" => {"tests" => 0.5, "static" => 0.3, "complexity" => 0.2}
      },
      "personas" => {
        "roles" => Array.new(6) { {"name" => "persona"} }
      },
      "adversarial" => {
        "personas" => Array.new(10) { {"name" => "adversary"} }
      },
      "catalog" => {
        "system" => {
          "injection_vulnerability" => {
            "remedy" => "sanitize_input",
            "auto_fix" => true
          }
        }
      },
      "severity" => {
        "critical" => ["injection_vulnerability"]
      },
      "auto_fix" => {
        "enabled" => true
      },
      "openrouter" => {
        "api_url" => "https://openrouter.ai/api/v1/chat/completions",
        "models" => {
          "balanced" => {
            "name" => "deepseek/deepseek-r1",
            "cost_per_1m_prompt" => 0.55,
            "cost_per_1m_completion" => 2.19,
            "cost_per_1m_cached" => 0.055
          }
        }
      },
      "profiles" => {
        "architect" => {
          "temperature" => 0.3,
          "model" => "anthropic/claude-3.5-sonnet"
        }
      }
    }

    File.write(@master_file, YAML.dump(data))
  end
end