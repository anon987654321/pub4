    assert_equal Master::Voice::Policy::FALLBACK["neural"], tts["neural"]
  end

  def test_standing_order_voice_directives_match_rules_voice_strunk
    voice = Master.load_yaml(File.join(DATA, "voice.yml"))
    strunk = voice.dig("voice", "strunk") || data.dig("voice", "strunk")
    orders = Master.load_yaml(Master.state_path)
    autocommit = orders.find { |order| order["name"] == "autocommit_post_chat" }

    assert_includes strunk.fetch("apply_to"), "prose"
    assert_match(/Strunk-style/, autocommit.fetch("description"))
    assert_includes strunk.fetch("hedges").fetch("en"), "will"
    assert_includes strunk.fetch("hedges").fetch("nb"), "kanskje"
  end

  private

  def rules
    Master.flatten_rules(merged_rules.fetch("rules", {}))
  end

  def data
    @data ||= Master.load_yaml(File.join(DATA, "rules.yml"))
  end

  def merged_rules
    @merged_rules ||= Master.load_rules(root: File.expand_path("..", __dir__))
  end

  def patterns
    @patterns ||= Master.load_yaml(File.join(DATA, "patterns.yml"))
  end

  def rule_reference_values(object)
    case object
    when Hash
      object.flat_map do |key, value|
        key.to_s == "rule" || key.to_s == "rules" ? Array(value).map(&:to_s) : rule_reference_values(value)
      end
    when Array
      object.flat_map { |value| rule_reference_values(value) }
    else