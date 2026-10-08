# frozen_string_literal: true

# public/assets must die before it is rebuilt. application.rb's
# excluded_paths line claims digest output is never input, but Propshaft
# does not exclude a SUBDIRECTORY of an included path — public/ is the load
# path and public/assets sits inside it, so every precompile re-digested
# the previous run's output (face-09726ccc-09726ccc.css on vm23, 27 stale
# face copies locally, and the rc script's rm -rf of assets/assets is a
# band-aid over the same defect). Clobber-first is SAFE here and only
# here: every MASTER/web asset source lives in public/ (that is the face's
# design), so the digested tree is fully regenerable — this is NOT the
# brgen situation, where clobber once broke a page whose asset existed
# only precompiled.
Rake::Task["assets:precompile"].enhance(["assets:clobber"]) if Rake::Task.task_defined?("assets:precompile")
