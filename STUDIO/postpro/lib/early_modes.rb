# frozen_string_literal: true

# What is wrong with this photograph, and which half a grade can reach.
#
# --rescue FILE diagnoses and stops. Add --output FILE and it applies the
# preset its findings point at. It names what it cannot fix every time, because
# three of the four layers a photograph fails on are beyond any grade, and a
# tool that quietly tries everything and reports success is lying about them.
if ARGV.include?("--rescue")
  require_relative "../rescue"
  subject = ARGV[ARGV.index("--rescue") + 1]
  if subject.nil? || !File.file?(subject)
    PostproBootstrap.dmesg("ERROR --rescue needs a readable file")
    exit 1
  end

  findings = Postpro::Rescue.diagnose(subject)
  Postpro::Rescue.report(findings).each { |line| PostproBootstrap.dmesg(line) }

  target = ARGV.include?("--output") ? ARGV[ARGV.index("--output") + 1] : nil
  preset = Postpro::Rescue.preset_for(findings)
  if target.nil?
    PostproBootstrap.dmesg("rescue: diagnosis only — pass --output FILE to apply " \
                           "#{preset || 'a grade'}")
    exit 0
  end
  if preset.nil?
    PostproBootstrap.dmesg("rescue: nothing to apply; the optical layer is already sound")
    exit 0
  end

  PostproBootstrap.dmesg("rescue: applying preset=#{preset}")
  out, status = Open3.capture2e(RbConfig.ruby, POSTPRO_ENTRY, "--input", subject,
                                "--output", target, "--preset", preset)
  unless status.success?
    PostproBootstrap.dmesg("ERROR rescue: the grade failed: #{out.lines.last.to_s.strip}")
    exit 1
  end

  require_relative "../uncanny"
  comparison = Postpro::Uncanny.compare(subject, target)
  Postpro::Uncanny.verdict(comparison).each { |line| PostproBootstrap.dmesg("rescue: #{line}") }
  PostproBootstrap.dmesg("rescue: wrote #{target}")
  exit 0
end

# What a set of frames says about itself: which frames are one photograph taken
# twice, and how far each frame's exposure sits from the set's own median. Both
# are readings, and the set is left as it was — moving a frame toward the
# median changes the graded look, which is the operator's decision.
if ARGV.include?("--set")
  require_relative "../frame_set"
  dir = ARGV[ARGV.index("--set") + 1]
  unless dir && File.directory?(dir)
    PostproBootstrap.dmesg("ERROR --set needs a directory of frames")
    exit 1
  end

  paths = Postpro::FrameSet.frames(dir)
  if paths.size < 2
    PostproBootstrap.dmesg("set #{dir}: #{paths.size} frame, and a set needs two")
    exit 0
  end

  Postpro::FrameSet.near_duplicates(paths).each do |pair|
    PostproBootstrap.dmesg("set duplicate: #{File.basename(pair.first)} ~ #{File.basename(pair.second)} " \
                           "(#{pair.distance}/64 bits differ)")
  end
  Postpro::FrameSet.exposure_offsets(paths).each do |path, stops|
    PostproBootstrap.dmesg(format("set exposure: %+.2f stops  %s", stops, File.basename(path)))
  end
  exit 0
end

# Four numbers on an image, or the delta across a grade. Handled here, straight
# after boot, because everything below this point can reach the interactive
# prompt — and a measurement that waits for a keypress is a measurement nobody
# puts in a script.
#
# Everything this file claims about putting texture back — the grain, the
# halation, the H&D shoulder — was an assertion until something measured it.
# `--measure FILE` reads one image; adding `--against AFTER` reads the pair and
# says which way each number moved and whether that is the direction film
# emulation should move it.
if ARGV.include?("--measure")
  require_relative "../uncanny"
  subject = ARGV[ARGV.index("--measure") + 1]
  if subject.nil? || !File.file?(subject)
    PostproBootstrap.dmesg("ERROR --measure needs a readable file")
    exit 1
  end

  against = ARGV.include?("--against") ? ARGV[ARGV.index("--against") + 1] : nil
  if against.nil?
    PostproBootstrap.dmesg("measure #{File.basename(subject)}: #{Postpro::Uncanny.read(subject)}")
    image = Vips::Image.new_from_file(subject, access: :random)
    PostproBootstrap.dmesg(format("measure %s: finest_octave=%.2f squint=%.2f", File.basename(subject),
                                  Postpro::Uncanny.finest_octave(image), Postpro::Uncanny.squint_image(image)))
    PostproBootstrap.dmesg("measure #{File.basename(subject)}: palette #{Postpro::Uncanny.palette_line(image)}")
  elsif !File.file?(against)
    PostproBootstrap.dmesg("ERROR --against #{against} is not a file")
    exit 1
  else
    comparison = Postpro::Uncanny.compare(subject, against)
    PostproBootstrap.dmesg("measure before: #{comparison[:before]}")
    PostproBootstrap.dmesg("measure after:  #{comparison[:after]}")
    Postpro::Uncanny.verdict(comparison).each { |line| PostproBootstrap.dmesg("measure #{line}") }
    [subject, against].each do |path|
      image = Vips::Image.new_from_file(path, access: :random)
      PostproBootstrap.dmesg("measure #{File.basename(path)}: palette #{Postpro::Uncanny.palette_line(image)}")
    end
  end
  exit 0
end
