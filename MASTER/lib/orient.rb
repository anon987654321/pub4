# frozen_string_literal: true

module Master
  module Orient
    BOOTSTRAP_FILES = %w[soul.yml rules.yml voice.yml style.yml limits.yml state.yml].freeze

    def self.render(root: Master::ROOT)
      BOOTSTRAP_FILES.map do |name|
        path = File.join(root, "data", name)
        next "# #{name}\n(not found)" unless File.file?(path)
        "# #{name}\n#{File.read(path, encoding: "UTF-8").rstrip}"
      end.join("\n\n")
    rescue StandardError => e
      "orient: #{e.message}"
    end
  end
end
