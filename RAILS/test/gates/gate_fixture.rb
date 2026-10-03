# frozen_string_literal: true

require "fileutils"

# Pointing a gate at a planted tree.
#
# A gate test that only runs the gate over this repository and asserts "clean"
# proves nothing: it passes just as well against a gate whose body is `return
# ok`. The test has to plant the defect the gate exists to catch, watch it fail,
# remove the defect and watch it pass.
#
# Each gate takes `root:` (the repository root it measures), defaulting to this
# checkout, so a test plants a tree in a temporary directory and passes it.
module GateFixture
  # Writes body at rel under dir, creating the directories rel names. Returns
  # the absolute path.
  def plant(dir, rel, body)
    path = File.join(dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  # An apps.yml the deploy inventory accepts. Every gate that walks the fleet
  # reads the fleet from here, so a fixture tree needs one before it has any
  # apps at all.
  def plant_apps_yml(dir, *names)
    rows = names.map do |name|
      "  #{name}:\n    domain: #{name}.test\n    port: 1\n" \
        "    deploy_script: #{name}.sh\n    deploy_root: /home/#{name}\n"
    end
    plant(dir, "RAILS/apps.yml", "apps:\n#{rows.join}")
  end
end
