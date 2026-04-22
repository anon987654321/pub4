require 'date'

# 1️⃣ Build the XML definition.
xml = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
    <Triggers>
      <TimeTrigger>
        <StartBoundary>#{Date.today.iso8601}T09:00:00</StartBoundary>
        <Enabled>true</Enabled>
      </TimeTrigger>
    </Triggers>
    <Actions>
      <Exec>
        <Command>notepad.exe</Command>
      </Exec>
    </Actions>
  </Task>
XML

# 2️⃣ Write to a temp file.
temp_path = File.join(ENV['TEMP'], "notepad_task_#{SecureRandom.hex(4)}.xml")
WriteFile.call(path: temp_path, content: xml)

begin
  # 3️⃣ Register the scheduled task.
  result = Shell.run(%{schtasks /Create /XML "#{temp_path}" /TN "DailyNotepad"})
  raise "Failed to create scheduled task (exit #{result.exitstatus})" unless result.success?
ensure
  # 4️⃣ Delete the temporary XML file.
  Shell.run(%{del "#{temp_path}"})
end
