# frozen_string_literal: true

puts [broken, {}.dig(:missing, :nested).inspect, { outer: {} }.dig(:outer, :missing, :nested).inspect,
          { outer: { inner: "value" } }.dig(:outer, :inner),
          Hash.ancestors.count { |a| a == Master::HashDigCompat }].join(" ")
  RUBY

  def test_hash_dig_compat_repairs_coltrane_dig_and_installs_once
    out, status = Open3.capture2e(RbConfig.ruby, "-e", COLTRANE_DIG_PROBE)

    assert status.success?, out
    assert_equal "raised nil nil value 1", out.strip
  end

  def test_the_suite_runs_on_mris_dig
    refute_includes Hash.ancestors.map(&:to_s), "Master::HashDigCompat"
  end
  def test_data_validation_detects_rapid_file_edits
    Dir.mktmpdir do |dir|
      data = File.join(dir, "data")
      FileUtils.mkdir_p(data)
      path = File.join(data, "sample.yml")
      File.write(path, "ok: true\n")
      Master.validate_data!(root: dir)

      File.write(path, "broken: [\n")
      errors = Master.validate_data!(root: dir)

      assert errors.key?("sample.yml"), errors.inspect
    end
  end

  def test_a_missing_yaml_file_warns_once
    Dir.mktmpdir do |dir|
      missing = File.join(dir, "PATH_OWNERSHIP.yml")
      _, err = capture_io { 3.times { assert_equal({}, Master.load_yaml(missing)) } }

      assert_equal 1, err.lines.grep(/load_yaml: /).size, err
    end
  end

  def test_missing_yaml_defaults_are_not_shared_between_calls
    Dir.mktmpdir do |dir|
      first = Master.load_yaml(File.join(dir, "first.yml"))
      first["polluted"] = true

      second = Master.load_yaml(File.join(dir, "second.yml"))

      assert_equal({}, second)
    end
  end

  # laws.yml needs aliases, which is why load_yaml allows them. Aliases are
  # references inside the document; a Ruby object tag is still refused.
  def test_load_yaml_preserves_false_root_values
    Dir.mktmpdir do |dir|
      path = File.join(dir, "false.yml")
      File.write(path, "false\n")

      assert_equal false, Master.load_yaml(path)
      assert_equal false, Master.load_yaml(path, default: "fallback")
    end
  end
