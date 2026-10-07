
  def test_checkpoint_uses_existing_checkpoint_store
    Dir.mktmpdir do |root|
      File.write(File.join(root, "file.txt"), "before")
      checkpoint = ->(id:, root:, files:) do
        Master::Fix::Checkpoint.new(root:, dir: File.join(root, ".master", "checkpoints")).create(
          label: "mission-#{id}", files:,
        )
      end
      mission = Master::Fix::Mission.new(root:, checkpoint:).start!(goal: "checkpoint", scope: root)
      mission.checkpoint!(files: ["file.txt"])

      checkpoint = mission.record["checkpoint"]
      assert checkpoint["id"]
      assert_equal ["file.txt"], checkpoint["files"]
      assert File.file?(File.join(root, ".master", "checkpoints", checkpoint["id"], "file.txt"))
    end
  end
  def test_v2_without_operator_is_normalized
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, ".master"))
      record = {
        "version" => 2, "id" => "old-v2", "state" => "waiting",
        "stage" => "verify", "goal" => "old", "scope" => root,
        "model" => "agy:auto", "effort" => "medium", "plan" => "inspect",
        "origin" => "fold", "auto_continue" => true
      }
      path = File.join(root, ".master", "mission.json")
      File.write(path, JSON.pretty_generate(record) + "\n")

      migrated = Master::Fix::Mission.current(root:)
      assert_equal "repair", migrated.dig("operator", "mode")
    end
  end

end