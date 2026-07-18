# frozen_string_literal: true

# Single resolve path for stream ENV so layers stop stomping each other.
# Order: best → stream extras → deep/fast → soft iterate → soft soul → producer mode force.
module DillaStreamEnv
  module_function

  def soft_fill!(table)
    table.each do |key, value|
      next if value.nil?
      ENV[key] = value.to_s if ENV[key].nil? || ENV[key].empty?
    end
  end

  def force_fill!(table)
    table.each do |key, value|
      next if value.nil?
      ENV[key] = value.to_s
    end
  end

  # Soft-fill iterate tuning — never overwrite keys already set (or locked by mode).
  def soft_fill_iterate!(tuning, locked_keys: [])
    locked = locked_keys.map(&:to_s)
    tuning.each do |key, value|
      next if value.nil?
      next if locked.include?(key.to_s)
      next if ENV[key] && !ENV[key].empty?
      ENV[key] = value.to_s
    end
  end

  def resolve_stream_env!(
    best_defaults:,
    deep_defaults:,
    extra_defaults:,
    fast_defaults:,
    iterate_tuning:,
    iterate_override_keys:,
    soul_defaults:,
    deep: false,
    iterate: false,
    soul: true
  )
    soft_fill!(best_defaults)
    soft_fill!(extra_defaults)
    if deep
      ENV["DILLA_DEEP"] = "1" if ENV["DILLA_DEEP"].to_s.empty?
      soft_fill!(deep_defaults)
    else
      fast = fast_defaults.dup
      if iterate
        iterate_override_keys.each { |key| fast.delete(key) }
      end
      # Fast defaults may intentionally clear gates — only soft-fill empties.
      soft_fill!(fast)
    end
    if iterate
      mode_keys = if defined?(DillaProducerModes)
                    DillaProducerModes.beauty_lock_keys
                  else
                    []
                  end
      soft_fill_iterate!(iterate_tuning, locked_keys: mode_keys)
      if soul
        soft_fill!(soul_defaults)
      end
    elsif soul
      soft_fill!(soul_defaults)
    end

    mode = ENV["PRODUCER_MODE"].to_s
    mode = ENV["RENDER_MODE"].to_s if mode.empty? && ENV["RENDER_MODE"].to_s == "camel"
    mode = "afta" if mode.empty? && ENV["STREAM_SOUL"] == "1"
    if defined?(DillaProducerModes) && !mode.empty?
      DillaProducerModes.apply!(mode, force: true)
    end
    mode
  end
end
