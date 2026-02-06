class Stream
  def initialize(output)
    @output = output
    @buffer = ""
  end

  def write_chunk(chunk)
    @buffer << chunk
    process_buffer
  end

  private

  def process_buffer
    lines = @buffer.split("\n")
    lines.each_slice(3) do |paragraph|
      formatted_paragraph = format_paragraph(paragraph)
      @output.write(formatted_paragraph)
    end
  end

  def format_paragraph(paragraph)
    paragraph.join("\n") + "\n\n"
  end
end

# Usage example
# output = YourOutputFormatter.new
# stream = Stream.new(output)
# stream.write_chunk("First line of the chunk.\nSecond line of the chunk.\nThird line of the chunk.\nFourth line of the chunk.")