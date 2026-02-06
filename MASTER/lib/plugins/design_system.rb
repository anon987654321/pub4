# frozen_string_literal: true

require 'yaml'

module MASTER
  module Plugins
    class DesignSystem
      @config = nil
      @config_mtime = nil
      @enabled = false

      class << self
        def config
          load_config unless @config
          @config
        end

        def load_config
          path = config_path
          return @config = default_config unless File.exist?(path)

          current_mtime = File.mtime(path)
          if @config && @config_mtime == current_mtime
            return @config
          end

          @config = YAML.load_file(path, symbolize_names: true)
          @config_mtime = current_mtime
          @config
        rescue => e
          warn "Failed to load design system config: #{e.message}"
          @config = default_config
        end

        def config_path
          File.join(__dir__, '..', 'config', 'plugins', 'design_system.yml')
        end

        def default_config
          {
            enabled: false,
            colors: { primary: '#007bff', secondary: '#6c757d' },
            typography: { base_size: 16, scale_ratio: 1.25 },
            spacing: { unit: 8, scale: [0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 16] },
            components: { prefix: 'ds-', namespace: 'DesignSystem' },
            accessibility: { wcag_level: 'AA', contrast_ratio: 4.5 }
          }
        end

        def enabled?
          @enabled
        end

        def enable
          @enabled = true
          load_config
          validate
        end

        def disable
          @enabled = false
        end

        def configure(options = {})
          load_config
          @config = @config.merge(options)
          validate
        end

        def apply(context = {})
          return { success: false, error: 'Plugin not enabled' } unless enabled?

          results = []
          
          # Apply color system
          if config[:colors]
            results << apply_colors(context)
          end

          # Apply typography
          if config[:typography]
            results << apply_typography(context)
          end

          # Apply spacing system
          if config[:spacing]
            results << apply_spacing(context)
          end

          # Apply component styles
          if config[:components]
            results << apply_components(context)
          end

          # Apply accessibility rules
          if config[:accessibility]
            results << apply_accessibility(context)
          end

          {
            success: true,
            applied: results.compact,
            timestamp: Time.now
          }
        rescue => e
          { success: false, error: e.message }
        end

        def validate
          errors = []
          errors.concat(validate_colors)
          errors.concat(validate_typography)
          errors.concat(validate_spacing)
          errors.concat(validate_components)
          errors.concat(validate_accessibility)
          errors.any? ? { valid: false, errors: errors } : { valid: true }
        end

        def validate_colors
          return [] unless config[:colors]
          return ['Colors must be a hash'] unless config[:colors].is_a?(Hash)
          
          config[:colors].filter_map do |key, value|
            next if value.is_a?(String) && value.match?(/^#[0-9A-Fa-f]{6}$/)
            "Invalid color format for #{key}: #{value}"
          end
        end

        def validate_typography
          return [] unless config[:typography]
          return ['Typography must be a hash'] unless config[:typography].is_a?(Hash)
          
          errors = []
          base_size = config[:typography][:base_size]
          errors << 'Base size must be positive' if base_size && !(base_size.is_a?(Numeric) && base_size > 0)
          ratio = config[:typography][:scale_ratio]
          errors << 'Scale ratio must be >= 1' if ratio && !(ratio.is_a?(Numeric) && ratio >= 1)
          errors
        end

        def validate_spacing
          return [] unless config[:spacing]
          return ['Spacing must be a hash'] unless config[:spacing].is_a?(Hash)
          
          errors = []
          unit = config[:spacing][:unit]
          errors << 'Spacing unit must be positive' if unit && !(unit.is_a?(Numeric) && unit > 0)
          errors << 'Spacing scale must be an array' if config[:spacing][:scale] && !config[:spacing][:scale].is_a?(Array)
          errors
        end

        def validate_components
          return [] unless config[:components]
          config[:components].is_a?(Hash) ? [] : ['Components must be a hash']
        end

        def validate_accessibility
          return [] unless config[:accessibility]
          
          errors = []
          level = config[:accessibility][:wcag_level]
          errors << 'Invalid WCAG level' if level && !%w[A AA AAA].include?(level)
          ratio = config[:accessibility][:contrast_ratio]
          errors << 'Contrast ratio must be positive' if ratio && !(ratio.is_a?(Numeric) && ratio > 0)
          errors
        end

        def colors
          config[:colors] || {}
        end

        def get_color(name)
          colors[name.to_sym]
        end

        def typography
          config[:typography] || {}
        end

        def font_size(level)
          base = typography[:base_size] || 16
          ratio = typography[:scale_ratio] || 1.25
          (base * (ratio ** level)).round(2)
        end

        def spacing
          config[:spacing] || {}
        end

        def spacing_value(index)
          unit = spacing[:unit] || 8
          scale = spacing[:scale] || [0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 16]
          return 0 if index >= scale.length
          unit * scale[index]
        end

        def components
          config[:components] || {}
        end

        def component_class(name)
          prefix = components[:prefix] || 'ds-'
          "#{prefix}#{name}"
        end

        def accessibility
          config[:accessibility] || {}
        end

        def check_contrast(fg_color, bg_color)
          # Calculate relative luminance and contrast ratio
          fg_lum = calculate_luminance(fg_color)
          bg_lum = calculate_luminance(bg_color)
          
          lighter = [fg_lum, bg_lum].max
          darker = [fg_lum, bg_lum].min
          
          ratio = (lighter + 0.05) / (darker + 0.05)
          
          wcag_level = accessibility[:wcag_level] || 'AA'
          min_ratio = wcag_level == 'AAA' ? 7.0 : 4.5
          
          {
            ratio: ratio.round(2),
            passes: ratio >= min_ratio,
            wcag_level: wcag_level,
            required_ratio: min_ratio
          }
        end

        private

        def apply_colors(context)
          {
            type: 'colors',
            data: colors,
            applied_to: context[:target] || 'global'
          }
        end

        def apply_typography(context)
          {
            type: 'typography',
            data: {
              base_size: typography[:base_size],
              scale_ratio: typography[:scale_ratio],
              sizes: (0..6).map { |i| font_size(i) }
            },
            applied_to: context[:target] || 'global'
          }
        end

        def apply_spacing(context)
          {
            type: 'spacing',
            data: {
              unit: spacing[:unit],
              scale: spacing[:scale],
              values: spacing[:scale]&.map&.with_index { |s, i| spacing_value(i) }
            },
            applied_to: context[:target] || 'global'
          }
        end

        def apply_components(context)
          {
            type: 'components',
            data: components,
            applied_to: context[:target] || 'global'
          }
        end

        def apply_accessibility(context)
          {
            type: 'accessibility',
            data: accessibility,
            applied_to: context[:target] || 'global'
          }
        end

        def calculate_luminance(hex_color)
          # Remove # if present
          hex = hex_color.sub(/^#/, '')
          
          # Convert to RGB
          r, g, b = hex.scan(/../).map { |c| c.to_i(16) / 255.0 }
          
          # Apply gamma correction
          r = r <= 0.03928 ? r / 12.92 : ((r + 0.055) / 1.055) ** 2.4
          g = g <= 0.03928 ? g / 12.92 : ((g + 0.055) / 1.055) ** 2.4
          b = b <= 0.03928 ? b / 12.92 : ((b + 0.055) / 1.055) ** 2.4
          
          # Calculate relative luminance
          0.2126 * r + 0.7152 * g + 0.0722 * b
        end
      end
    end
  end
end
