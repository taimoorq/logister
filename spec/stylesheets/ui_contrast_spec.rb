require "rails_helper"

RSpec.describe "UI contrast contract" do
  stylesheet = Rails.root.join("app/assets/stylesheets/application.tailwind.css").read
  root_tokens = stylesheet.match(/:root\s*\{(?<body>.*?)^\s*\}/m)[:body]
  tokens = root_tokens.scan(/(?<name>--[\w-]+):\s*(?<value>[^;]+);/).to_h.transform_values(&:strip)

  checks = [
    [ "primary text on surface", "--app-text", "--app-surface", 4.5 ],
    [ "muted text on surface", "--app-muted", "--app-surface", 4.5 ],
    [ "muted text on subtle surface", "--app-muted", "--app-surface-subtle", 4.5 ],
    [ "placeholder text on surface", "--app-placeholder", "--app-surface", 4.5 ],
    [ "control border on surface", "--app-control-border", "--app-surface", 3.0 ],
    [ "control border on subtle surface", "--app-control-border", "--app-surface-subtle", 3.0 ],
    [ "focus indicator on surface", "--app-focus", "--app-surface", 3.0 ],
    [ "selected navigation text", "--app-selection-contrast", "--app-selection", 4.5 ],
    [ "selected navigation hover text", "--app-selection-contrast", "--app-selection-hover", 4.5 ],
    [ "danger text on danger surface", "--app-danger-800", "--app-danger-50", 4.5 ],
    [ "danger control boundary on surface", "--app-danger-700", "--app-surface", 3.0 ],
    [ "warning text on warning surface", "--app-warning-700", "--app-warning-50", 4.5 ],
    [ "success text on success surface", "--app-success-700", "--app-success-50", 4.5 ],
    [ "archived text on archived surface", "--app-archived-800", "--app-archived-50", 4.5 ]
  ]

  def resolve_color(tokens, name, seen = [])
    raise "Circular color token reference: #{(seen + [ name ]).join(' -> ')}" if seen.include?(name)

    value = tokens.fetch(name)
    reference = value.match(/\Avar\((--[\w-]+)\)\z/)
    return resolve_color(tokens, reference[1], seen + [ name ]) if reference

    raise "#{name} must resolve to an opaque six-digit hex color, got #{value.inspect}" unless value.match?(/\A#[0-9a-f]{6}\z/i)
    value
  end

  def relative_luminance(hex)
    channels = hex.delete_prefix("#").scan(/../).map { |channel| channel.to_i(16) / 255.0 }
    linear = channels.map { |channel| channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4 }

    (0.2126 * linear[0]) + (0.7152 * linear[1]) + (0.0722 * linear[2])
  end

  def contrast_ratio(foreground, background)
    lighter, darker = [ relative_luminance(foreground), relative_luminance(background) ].sort.reverse
    (lighter + 0.05) / (darker + 0.05)
  end

  it "keeps approved semantic color pairs at WCAG 2.2 AA contrast" do
    failures = checks.filter_map do |label, foreground_role, background_role, minimum|
      foreground = resolve_color(tokens, foreground_role)
      background = resolve_color(tokens, background_role)
      ratio = contrast_ratio(foreground, background)

      next if ratio >= minimum

      "#{label}: #{ratio.round(2)}:1 (requires #{minimum}:1; #{foreground_role} #{foreground} on #{background_role} #{background})"
    end

    expect(failures).to be_empty, "Contrast failures:\n#{failures.join("\n")}"
  end
end
