# frozen_string_literal: true

require_relative "test_helper"

class TestPersonalWorkspace < Minitest::Test
  def setup
    @root = Dir.mktmpdir("master-ws-")
    Fiber[:master_pair_subject] = nil
  end

  def teardown
    FileUtils.rm_rf(@root)
    Fiber[:master_pair_subject] = nil
    Fiber[:master_visitor] = nil
  end

  def grant_personal_memory(subject)
    Master::Ground::PersonalPermissions.new(root: @root).grant(
      scope: "personal_memory", subject:, confirmed_by: "local owner",
      purpose: Master::Ground::PersonalWorkspace::MEMORY_PERMISSION_PURPOSE
    )
  end

  def test_ensure_writes_owner_only_user_and_memory_files
    dir = Master::Ground::PersonalWorkspace.ensure!(root: @root, subject: "abc123")
    user = File.join(dir, "USER.md")
    memory = File.join(dir, "MEMORY.md")

    assert File.file?(user)
    assert File.file?(memory)
    assert_equal 0o700, File.stat(File.dirname(dir)).mode & 0o777
    assert_equal 0o700, File.stat(dir).mode & 0o777
    [user, memory].each { |path| assert_equal 0o600, File.stat(path).mode & 0o777 }
  end

  def test_snapshot_requires_consent_and_returns_both_personal_files
    assert_raises(Master::Ground::PersonalWorkspace::PermissionDenied) do
      Master::Ground::PersonalWorkspace.snapshot(root: @root, subject: "sub1")
    end

    grant_personal_memory("sub1")
    dir = Master::Ground::PersonalWorkspace.ensure!(root: @root, subject: "sub1")
    File.write(File.join(dir, "USER.md"), "# USER\n- Name: Jules\n")
    File.write(File.join(dir, "MEMORY.md"), "# MEMORY\nPrefers tea\n")

    snapshot = Master::Ground::PersonalWorkspace.snapshot(root: @root, subject: "sub1")
    assert_includes snapshot.fetch("USER.md"), "Jules"
    assert_includes snapshot.fetch("MEMORY.md"), "Prefers tea"
  end

  def test_snapshot_refuses_symlinked_personal_files
    grant_personal_memory("sub1")
    dir = File.join(@root, Master::Ground::PersonalWorkspace::REL, "sub1")
    FileUtils.mkdir_p(dir)
    outside = File.join(@root, "outside.txt")
    File.write(outside, "private external content")
    File.symlink(outside, File.join(dir, "USER.md"))

    assert_raises(Master::Ground::PersonalWorkspace::PermissionDenied) do
      Master::Ground::PersonalWorkspace.snapshot(root: @root, subject: "sub1")
    end
  end

  def test_forget_memory_clears_durable_notes_but_preserves_profile
    grant_personal_memory("sub1")
    dir = Master::Ground::PersonalWorkspace.ensure!(root: @root, subject: "sub1")
    user = File.join(dir, "USER.md")
    memory = File.join(dir, "MEMORY.md")
    File.write(user, "# USER\n- Name: Jules\n")
    File.write(memory, "# MEMORY\n\n## 2026-10-21 general secret\n\nPrefers tea\n")

    assert Master::Ground::PersonalWorkspace.forget_memory!(root: @root, subject: "sub1")
    assert_includes File.read(user), "Jules"
    refute_includes File.read(memory), "Prefers tea"
    assert_includes File.read(memory), "Durable notes"
  end

  def test_prompt_section_reads_the_fiber_subject
    Master::Ground::PersonalWorkspace.ensure!(root: @root, subject: "sub1")
    File.write(File.join(@root, ".master", "workspace", "sub1", "USER.md"), "I am Jules")
    Fiber[:master_pair_subject] = "sub1"
    grant_personal_memory("sub1")

    section = Master::Ground::PersonalWorkspace.prompt_section(@root)
    assert_includes section, "Personal workspace"
    assert_includes section, "I am Jules"
  end

  def test_append_memory_stays_in_the_subject_dir
    grant_personal_memory("sub1")
    path = Master::Ground::PersonalWorkspace.append_memory(
      root: @root, subject: "sub1", key: "prefers_tea", body: "drinks tea", type: "user",
    )
    refute_includes path, "project_context.yml"
    assert_includes File.read(path), "prefers_tea"
    assert_includes File.read(path), "drinks tea"
  end

  def test_pulse_is_heartbeat_ok_without_nudges
    Master::Ground::PersonalWorkspace.ensure!(root: @root, subject: "sub1")
    assert_equal "HEARTBEAT_OK", Master::Ground::PersonalWorkspace.pulse(root: @root)
  end

  def test_persisted_device_owner_is_not_loaded_for_a_visitor
    Master::Device::Agent.stub(:owner_subject, "owner") do
      Master::Device::Agent.stub(:paired?, true) do
        Fiber[:master_visitor] = true
        assert_nil Master::Ground::PersonalWorkspace.prompt_section(@root)
      ensure
        Fiber[:master_visitor] = nil
      end
    end
  end

  def test_persisted_device_owner_is_used_for_memory_only_in_a_local_context
    Master::Device::Agent.stub(:paired?, true) do
      Master::Device.stub(:android?, true) do
        Master::Device::Agent.stub(:owner_subject, "owner123") do
          Fiber[:master_pair_subject] = nil
          Fiber[:master_visitor] = nil
          grant_personal_memory("owner123")
          tool = Master::Io::MemoryRecord.new(memory: nil, root: @root)
          result = tool.call(key: "likes_tea", description: "pref", body: "drinks tea", type: "user")
          assert result.ok?, result.inspect
          assert_includes result.value!, "owner123/MEMORY.md"
        end
      end
    end
  ensure
    Fiber[:master_pair_subject] = nil
    Fiber[:master_visitor] = nil
  end

  def test_memory_record_writes_to_workspace_when_paired
    Fiber[:master_pair_subject] = "sub1"
    grant_personal_memory("sub1")
    tool = Master::Io::MemoryRecord.new(memory: nil, root: @root)
    result = tool.call(key: "likes_tea", description: "pref", body: "drinks tea", type: "user")
    assert result.ok?, result.inspect
    refute_includes result.value!, "project_context.yml"
    assert_includes File.read(File.join(@root, ".master", "workspace", "sub1", "MEMORY.md")), "likes_tea"
  ensure
    Fiber[:master_pair_subject] = nil
  end

  def test_unpaired_user_facts_never_fall_back_to_shared_project_context
    tool = Master::Io::MemoryRecord.new(memory: nil, root: @root)
    result = tool.call(key: "likes_tea", description: "pref", body: "drinks tea", type: "user")

    refute result.ok?
    assert_equal :policy, result.category
    assert_match(/refusing to write them to shared project_context/, result.message)
    refute File.exist?(File.join(@root, "data", "project_context.yml"))
  end

  # The shared context is tracked and pushed: no visitor writes it, and no secret reaches it.
  def test_a_visitor_never_writes_the_shared_project_context
    Fiber[:master_visitor] = true
    result = Master::Io::MemoryRecord.new(memory: nil, root: @root)
                                     .call(key: "deploy_note", description: "x", body: "y", type: "project")

    refute result.ok?
    refute File.exist?(File.join(@root, "data", "project_context.yml"))
  ensure
    Fiber[:master_visitor] = nil
  end

  def test_a_secret_in_a_project_entry_is_redacted_before_it_is_written
    token = "sk-" + ("a" * 40)
    Master::Io::MemoryRecord.new(memory: nil, root: @root)
                            .call(key: "deploy_note", description: "key", body: "use #{token} for deploys", type: "project")

    refute_includes File.read(File.join(@root, "data", "project_context.yml")), token
  end

  def test_paired_personal_memory_is_denied_until_its_subject_grants_consent
    Fiber[:master_pair_subject] = "sub1"
    tool = Master::Io::MemoryRecord.new(memory: nil, root: @root)
    result = tool.call(key: "likes_tea", description: "pref", body: "drinks tea", type: "user")

    refute result.ok?
    assert_equal :policy, result.category
    refute File.exist?(File.join(@root, ".master", "workspace", "sub1", "MEMORY.md"))
  ensure
    Fiber[:master_pair_subject] = nil
  end

  def test_owner_profile_is_not_read_or_written_without_the_personal_memory_grant
    subject = "sub1"
    path = File.join(Master::Ground::PersonalWorkspace.dir_for(subject, root: @root), "USER.md")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "# USER\n- Name: Secret\n")

    assert_empty Master::Device::OwnerProfile.values(root: @root, subject:)
    assert_raises(Master::Ground::PersonalWorkspace::PermissionDenied) do
      Master::Device::OwnerProfile.set(root: @root, subject:, name: "Changed")
    end
    assert_includes File.read(path), "Secret"
    refute_includes File.read(path), "Changed"
  end

  def test_pulse_reports_a_todo_line
    Master::Ground::PersonalWorkspace.ensure!(root: @root, subject: "sub1")
    File.write(File.join(@root, ".master", "workspace", "sub1", "MEMORY.md"), "TODO: call back\n")
    assert_match(/pulse: sub1 TODO: call back/, Master::Ground::PersonalWorkspace.pulse(root: @root))
  end
end
