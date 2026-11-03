# frozen_string_literal: true

require "json"
require "uri"

module Studio
  # Media capability contract owned by Studio. Keeping the contract in code
  # makes every emulation direction discoverable by MASTER, addressable by a
  # stable id, and regression-testable after the design notes are gone.
    module AnalogCapabilities
      POSTPRO = %i[
        exposure_linked_grain per_channel_grain_size shadow_grain_clumping halation_threshold
        red_sensitive_halation gate_weave light_leaks lens_flare_ghosts aperture_bokeh
        focus_breathing chromatic_focus_shift focal_length_vignette film_coordinate_dust
        coherent_scratches rgb_scan_misregistration scanner_row_banding contact_sheet_borders
        uneven_development push_process_curve pull_process_curve silver_monochrome_grain
        cyan_shadow_crossover warm_highlight_crossover print_paper_dmax flare_black_lift
        stock_highlight_shoulder spectral_stock_sensitivity tungsten_filter_cast
        fluorescent_green_bias disposable_flash_falloff polaroid_dye_spread polaroid_drying_drift
        instant_film_edge_failure vhs_luma_bleed vhs_chroma_delay vhs_head_switch_band
        vhs_tracking_noise vhs_interlace_combing crt_phosphor_bloom crt_scanlines
        minidv_block_dropout hi8_chroma_noise super8_gate_flutter super8_bloom
        sixteen_mm_grain thirtyfive_mm_grain medium_format_smoothness backlight_lens_haze
        diffusion_mtf promist_highlight_spread net_diffusion split_diopter_mask
        reciprocity_failure film_curl_warp wet_gate_scratch_suppression lab_print_luts
        neutral_grey_calibration skin_tone_protection scene_stock_recommendation
        nondestructive_comparison parameter_seed metadata_sidecar reference_match_metrics
        clipping_warning skin_hue_warning grain_zoom_check vhs_legibility_check
        temporal_consistency_check codec_artifact_preview reversible_recipe
      ].freeze

      REPLICATE = %i[
        stock_prompt lens_prompt camera_height distance_crop lighting_direction plastic_skin_negative
        identity_first_pass style_second_pass candidate_ranking likeness_confidence face_crop_comparison
        expression_diversity pose_diversity wardrobe_diversity background_diversity duplicate_detection
        caption_lint trigger_collision checkpoint_gallery fixed_prompt_regression seed_ledger
        prompt_provenance checkpoint_discovery training_status checkpoint_readiness newest_safe_checkpoint
        training_not_ready consent_manifest subject_removal expiry_policy local_assets_only cost_estimate
        aspect_intent portrait_default editorial_landscape batch_variations film_vocabulary
        bergen_weather time_of_day lens_distortion natural_imperfections anti_beautification
        age_preservation skin_texture_gate hand_review text_image_refusal output_url_validation
        download_checksum content_cache transient_retry provider_audit timeout_cancellation
        model_capabilities schema_validation input_key_adaptation preview_mode final_mode
        postpro_handoff alt_text gallery_manifest
      ].freeze

      DILLA = %i[
        hit_microtiming nonrepeating_swing velocity_drift note_length_drift late_kick_lane
        early_snare_lane ahead_hat_clusters ghost_accent_maps triplet_intrusions tuplet_fills
        pattern_mutation call_response_fills hihat_choke_groups mpc_velocity_curve mpc_twelve_bit
        sp1200_bandwidth s950_pitch_resampling cassette_wow_random_walk transient_flutter
        bandwidth_shaped_hiss program_ducked_hiss print_through tape_start tape_stop splice_clicks
        vinyl_crackle_density groove_lock_pulse turntable_rumble stylus_mistracking offcentre_wow
        stereo_dust_clicks needle_drop_fade mono_low_end dynamic_bass_saturation imperfect_sidechain
        parallel_drum_crush tape_transient_softening transformer_colour console_crosstalk
        narrow_hf_stereo haas_jitter spring_reverb plate_damping chamber_reflections
        saturated_dub_delay self_oscillation_cap chorus_phase_drift bbd_noise rhodes_tines
        wurli_tremolo mellotron_variance solina_drift fm_bell_detune granular_chop_jitter
        reverse_cymbal_swell jazz_chop_envelopes key_detection modal_interchange quartal_voicings
        cluster_density bass_voice_leading arrangement_energy eight_bar_dropouts four_bar_pickups
        one_bar_mutes reference_loudness true_peak_guard delivery_lufs mono_compatibility
        spectral_regression
      ].freeze

      GROUPS = { postpro: POSTPRO, replicate: REPLICATE, dilla: DILLA }.freeze
      OFFSETS = { postpro: 1, replicate: 71, dilla: 131 }.freeze

      # This is an inventory of directions, not proof that each direction is
      # implemented. Promotion out of :unverified requires a concrete code path
      # and a regression test; otherwise readiness would be a guess.
      IMPLEMENTATION_STATUS = {}.freeze
      STATUSES = %i[verified unavailable unverified].freeze

      module_function

      def implementation_record(component, key)
        IMPLEMENTATION_STATUS.fetch([component.to_sym, key.to_sym]) do
          { status: :unverified, implementation: nil, evidence: nil, regression_test: nil }.freeze
        end
      end

      # Readiness references are executable contracts, not free-form claims.
      # Resolve local path#method references under the repository root; a file
      # or method that does not exist cannot promote a capability.
      def local_source_reference?(value)
        return false unless value.is_a?(String) && value.frozen? && !value.strip.empty?

        path, member = value.split("#", 2)
        return false unless path && !path.empty? && member&.match?(/\A[a-z_]\w*[!?]?\z/i)

        root = File.realpath(File.expand_path("../..", __dir__))
        target = File.realpath(File.expand_path(path, root))
        return false unless target.start_with?("#{root}#{File::SEPARATOR}")
        return false unless File.file?(target)

        definition = /^\s*def\s+#{Regexp.escape(member)}(?=\s|\(|$)/
        File.foreach(target).any? { |line| line.match?(definition) }
      rescue StandardError
        false
      end

      def evidence_reference?(value)
        return true if local_source_reference?(value)
        return false unless value.is_a?(String) && value.frozen? && !value.strip.empty?

        uri = URI.parse(value)
        uri.is_a?(URI::HTTPS) && !uri.host.to_s.empty?
      rescue URI::InvalidURIError
        false
      end

      # A status may leave :unverified only with a concrete source method and
      # its real regression test. :unavailable needs a source or HTTPS evidence
      # reference plus a real test proving the boundary; a bare flag is not enough.
      def valid_implementation_record?(component, key, record)
        return false unless component.is_a?(Symbol) && key.is_a?(Symbol)
        return false unless GROUPS.key?(component) && GROUPS.fetch(component).include?(key)
        return false unless record.is_a?(Hash) && record.frozen?
        return false unless STATUSES.include?(record[:status])

        case record[:status]
        when :unverified
          record[:implementation].nil? && record[:evidence].nil? && record[:regression_test].nil?
        when :verified
          local_source_reference?(record[:implementation]) &&
            local_source_reference?(record[:regression_test]) && record[:evidence].nil?
        when :unavailable
          evidence_reference?(record[:evidence]) &&
            local_source_reference?(record[:regression_test]) && record[:implementation].nil?
        else
          false
        end
      end

      def implementation_status(component, key)
        implementation_record(component, key).fetch(:status, :unverified)
      end

      def enabled_for(status)
        return true if status == :verified
        return false if status == :unavailable

        nil
      end

      def all
        @all ||= GROUPS.flat_map do |component, keys|
          keys.each_with_index.map do |key, index|
            id = OFFSETS.fetch(component) + index
            record = implementation_record(component, key)
            status = record.fetch(:status, :unverified)
            {
              id:, key:, component:, stage: stage_for(component, id),
              description: key.to_s.tr("_", " ").freeze,
              catalogued: true, status:, enabled: enabled_for(status),
              implementation: record[:implementation], evidence: record[:evidence],
              regression_test: record[:regression_test]
            }.freeze
          end
        end.freeze
      end

      def fetch(id_or_key)
        needle = id_or_key.to_s
        all.find { |entry| entry[:id].to_s == needle || entry[:key].to_s == needle }
      end

      def stage_for(component, id)
        case component
        when :postpro then postpro_stage(id)
        when :replicate then replicate_stage(id)
        when :dilla then dilla_stage(id)
        end
      end

      def postpro_stage(id)
        case id
        when ..58 then :image_pipeline
        when ..63 then :grade_workflow
        else :quality_gate
        end
      end

      def replicate_stage(id)
        case id
        when ..78 then :prompt_pipeline
        when ..92 then :identity_review
        when ..101 then :lora_lifecycle
        else :provider_pipeline
        end
      end

      def dilla_stage(id)
        case id
        when ..147 then :performance_engine
        when ..176 then :analog_signal_chain
        when ..191 then :harmony_engine
        when ..195 then :arrangement_engine
        else :mastering_gate
        end
      end

      def for(component)
        all.select { |entry| entry[:component] == component.to_sym }
      end

      def profile(component, intensity: 0.5, seed: 0)
        raise ArgumentError, "unknown component: #{component}" unless GROUPS.key?(component.to_sym)

        entries = self.for(component)
        {
          component: component.to_sym,
          seed: Integer(seed),
          intensity: Float(intensity).clamp(0.0, 1.0),
          capabilities: entries.to_h { |entry| [entry[:key], entry[:enabled]] },
          capability_status: entries.to_h { |entry| [entry[:key], entry[:status]] },
        }
      end

      def report(component = nil)
        entries = component ? self.for(component) : all
        JSON.pretty_generate(
          version: 1,
          count: entries.length,
          catalog_complete: entries.length == (component ? GROUPS.fetch(component.to_sym).length : 200),
          complete: entries.all? { |entry| entry[:enabled] == true },
          enabled_count: entries.count { |entry| entry[:enabled] == true },
          unavailable_count: entries.count { |entry| entry[:status] == :unavailable },
          unverified_count: entries.count { |entry| entry[:status] == :unverified },
          capabilities: entries,
        )
      end

      def validate!
        raise "analog capability contract must contain ids 1..200" unless all.map { |e| e[:id] } == (1..200).to_a
        raise "analog capability keys must be unique" unless all.map { |e| e[:key] }.uniq.length == 200
        raise "analog capability status is invalid" unless all.all? { |entry| STATUSES.include?(entry[:status]) }
        raise "verified capability must be enabled" unless all.all? { |entry| entry[:status] != :verified || entry[:enabled] == true }
        raise "unavailable capability must be disabled" unless all.all? { |entry| entry[:status] != :unavailable || entry[:enabled] == false }
        raise "unverified capability must not claim enabled or disabled" unless all.all? { |entry| entry[:status] != :unverified || entry[:enabled].nil? }
        invalid_keys = IMPLEMENTATION_STATUS.keys.reject do |identity|
          identity.is_a?(Array) && identity.length == 2 && identity.frozen?
        end
        raise "implementation status keys must be frozen [component, key] pairs" unless invalid_keys.empty?
        invalid = IMPLEMENTATION_STATUS.filter_map do |(component, key), record|
          [component, key] unless valid_implementation_record?(component, key, record)
        end
        raise "implementation status lacks valid implementation/evidence and regression references: #{invalid.inspect}" unless invalid.empty?
        true
      end
    end
end

Studio::AnalogCapabilities.validate!
