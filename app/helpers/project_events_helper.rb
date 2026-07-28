# frozen_string_literal: true

module ProjectEventsHelper
  def android_stacktrace_text(cause_chain)
    cause_chain.flat_map do |entry|
      [ "#{entry[:type]}: #{entry[:message]}".strip, *android_stacktrace_frames(entry[:frames]) ]
    end.join("\n")
  end

  private

  def android_stacktrace_frames(frames)
    frames.map do |frame|
      method_name = frame[:qualified_method].presence || frame[:method_name]
      location = "#{frame[:file]}#{":#{frame[:line_number]}" if frame[:line_number]}"
      "  at #{method_name}(#{location})"
    end
  end
end
