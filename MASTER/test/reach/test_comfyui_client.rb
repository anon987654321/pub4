# frozen_string_literal: true

require_relative "../test_helper"

class TestComfyuiClient < Minitest::Test
  def setup
    @root = Dir.mktmpdir("comfyui_client")
    @workflow_path = File.join(@root, "workflow.json")
    @inputs_path = File.join(@root, "inputs.yml")
    File.write(@workflow_path, {
      "6" => { "class_type" => "CLIPTextEncode", "inputs" => { "text" => "old" } },
      "10" => { "class_type" => "LoadImage", "inputs" => { "image" => "old.png" } },
      "22" => { "class_type" => "ADE_AnimateDiffLoRALoader", "inputs" => { "lora_name" => "old.safetensors", "strength" => 0.5 } },
    }.to_json)
    File.write(@inputs_path, <<~YAML)
      image: "10.inputs.image"
      prompt: "6.inputs.text"
      motion_lora: "22.inputs.lora_name"
      motion_lora_strength: "22.inputs.strength"
    YAML
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_patch_workflow_applies_inputs_map
    client = Master::Reach::ComfyuiClient.new(
      base_url: "http://127.0.0.1:8188",
      workflow_path: @workflow_path,
      inputs_map_path: @inputs_path
    )
    workflow = client.send(:load_workflow)
    client.send(
      :patch_workflow!,
      workflow,
      image: "keyframe.png",
      prompt: "slow dolly push-in",
      motion_lora: "ZIKI_dolly_v1.safetensors",
      motion_lora_strength: 0.82
    )
    assert_equal "keyframe.png", workflow.dig("10", "inputs", "image")
    assert_equal "slow dolly push-in", workflow.dig("6", "inputs", "text")
    assert_equal "ZIKI_dolly_v1.safetensors", workflow.dig("22", "inputs", "lora_name")
    assert_in_delta 0.82, workflow.dig("22", "inputs", "strength")
  end
end