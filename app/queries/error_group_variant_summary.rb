# frozen_string_literal: true

class ErrorGroupVariantSummary
  Variant = Data.define(:key, :label, :events, :share, :last_seen_at)
  Result = Data.define(:variants, :total_events, :classified_events, :coverage) do
    def available?
      variants.size >= 2
    end
  end

  def self.call(group:, occurrence_scope: nil)
    new(group:, occurrence_scope:).call
  end

  attr_reader :group, :occurrence_scope

  def initialize(group:, occurrence_scope: nil)
    @group = group
    @occurrence_scope = occurrence_scope
  end

  def call
    scope = (occurrence_scope || group.error_occurrences).where(error_group_id: group.id)
    total = scope.count
    rows = scope
      .where("COALESCE(dimensions ->> 'variant_key', '') <> ''")
      .group(
        Arel.sql("dimensions ->> 'variant_key'"),
        Arel.sql("dimensions ->> 'variant_label'")
      )
      .pluck(
        Arel.sql("dimensions ->> 'variant_key'"),
        Arel.sql("dimensions ->> 'variant_label'"),
        Arel.sql("COUNT(*)"),
        Arel.sql("MAX(error_occurrences.occurred_at)")
      )
    classified = rows.sum { |row| row[2].to_i }
    variants = rows.map do |key, label, count, last_seen_at|
      Variant.new(
        key:,
        label: label.to_s.presence || "App call path #{key.to_s.first(8)}",
        events: count.to_i,
        share: classified.positive? ? count.to_i.fdiv(classified).round(4) : 0.0,
        last_seen_at:
      )
    end.sort_by { |variant| [ -variant.events, variant.label, variant.key ] }.freeze
    Result.new(
      variants:,
      total_events: total,
      classified_events: classified,
      coverage: total.positive? ? classified.fdiv(total).round(4) : 0.0
    ).freeze
  end
end
