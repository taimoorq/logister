require "base64"
require "json"

module TableCursorPagination
  extend ActiveSupport::Concern

  DEFAULT_PER_PAGE = 50
  MAX_PER_PAGE = 100

  CursorPage = Struct.new(
    :records,
    :previous_cursor,
    :next_cursor,
    :has_previous,
    :has_next,
    :per_page,
    keyword_init: true
  ) do
    def has_previous? = has_previous
    def has_next? = has_next
  end

  private

  def cursor_page(relation, before: nil, after: nil, per_page: DEFAULT_PER_PAGE, timestamp_column: :occurred_at)
    limit = normalized_per_page(per_page)
    timestamp_column = normalized_timestamp_column(timestamp_column)
    after_cursor = decode_table_cursor(after, timestamp_column:)
    before_cursor = after_cursor.present? ? nil : decode_table_cursor(before, timestamp_column:)

    if after_cursor.present?
      rows = newer_than_cursor(relation, after_cursor, timestamp_column:)
             .reorder(timestamp_column => :asc, id: :asc)
             .limit(limit + 1)
             .to_a
      has_extra = rows.length > limit
      records = rows.first(limit).reverse
      has_previous = has_extra
      has_next = records.any?
    else
      scoped = before_cursor.present? ? older_than_cursor(relation, before_cursor, timestamp_column:) : relation
      rows = scoped.reorder(timestamp_column => :desc, id: :desc)
                   .limit(limit + 1)
                   .to_a
      has_extra = rows.length > limit
      records = rows.first(limit)
      has_previous = before_cursor.present? && records.any?
      has_next = has_extra
    end

    CursorPage.new(
      records: records,
      previous_cursor: records.any? ? encode_table_cursor(records.first, timestamp_column:) : nil,
      next_cursor: records.any? ? encode_table_cursor(records.last, timestamp_column:) : nil,
      has_previous: has_previous,
      has_next: has_next,
      per_page: limit
    )
  end

  def normalized_per_page(value)
    size = value.to_i
    return DEFAULT_PER_PAGE unless size.positive?

    [ size, MAX_PER_PAGE ].min
  end

  def older_than_cursor(relation, cursor, timestamp_column:)
    relation.where(
      "ingest_events.#{timestamp_column} < :timestamp OR (ingest_events.#{timestamp_column} = :timestamp AND ingest_events.id < :id)",
      cursor
    )
  end

  def newer_than_cursor(relation, cursor, timestamp_column:)
    relation.where(
      "ingest_events.#{timestamp_column} > :timestamp OR (ingest_events.#{timestamp_column} = :timestamp AND ingest_events.id > :id)",
      cursor
    )
  end

  def encode_table_cursor(record, timestamp_column:)
    Base64.urlsafe_encode64(
      { timestamp: record.public_send(timestamp_column).utc.iso8601(6), timestamp_column: timestamp_column.to_s, id: record.id }.to_json,
      padding: false
    )
  end

  def decode_table_cursor(value, timestamp_column:)
    return nil if value.blank?

    payload = JSON.parse(Base64.urlsafe_decode64(value.to_s))
    encoded_column = payload["timestamp_column"].presence || "occurred_at"
    return nil unless encoded_column == timestamp_column.to_s

    timestamp = Time.zone.iso8601((payload["timestamp"] || payload["occurred_at"]).to_s)
    id = Integer(payload.fetch("id"))
    return nil unless id.positive?

    { timestamp:, id: }
  rescue ArgumentError, KeyError, JSON::ParserError
    nil
  end

  def normalized_timestamp_column(value)
    value.to_sym == :created_at ? :created_at : :occurred_at
  end
end
