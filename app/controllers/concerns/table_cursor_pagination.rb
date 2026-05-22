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

  def cursor_page(relation, before: nil, after: nil, per_page: DEFAULT_PER_PAGE)
    limit = normalized_per_page(per_page)
    after_cursor = decode_table_cursor(after)
    before_cursor = after_cursor.present? ? nil : decode_table_cursor(before)

    if after_cursor.present?
      rows = newer_than_cursor(relation, after_cursor)
             .reorder(occurred_at: :asc, id: :asc)
             .limit(limit + 1)
             .to_a
      has_extra = rows.length > limit
      records = rows.first(limit).reverse
      has_previous = has_extra
      has_next = records.any?
    else
      scoped = before_cursor.present? ? older_than_cursor(relation, before_cursor) : relation
      rows = scoped.reorder(occurred_at: :desc, id: :desc)
                   .limit(limit + 1)
                   .to_a
      has_extra = rows.length > limit
      records = rows.first(limit)
      has_previous = before_cursor.present? && records.any?
      has_next = has_extra
    end

    CursorPage.new(
      records: records,
      previous_cursor: records.any? ? encode_table_cursor(records.first) : nil,
      next_cursor: records.any? ? encode_table_cursor(records.last) : nil,
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

  def older_than_cursor(relation, cursor)
    relation.where(
      "ingest_events.occurred_at < :occurred_at OR (ingest_events.occurred_at = :occurred_at AND ingest_events.id < :id)",
      cursor
    )
  end

  def newer_than_cursor(relation, cursor)
    relation.where(
      "ingest_events.occurred_at > :occurred_at OR (ingest_events.occurred_at = :occurred_at AND ingest_events.id > :id)",
      cursor
    )
  end

  def encode_table_cursor(record)
    Base64.urlsafe_encode64(
      { occurred_at: record.occurred_at.utc.iso8601(6), id: record.id }.to_json,
      padding: false
    )
  end

  def decode_table_cursor(value)
    return nil if value.blank?

    payload = JSON.parse(Base64.urlsafe_decode64(value.to_s))
    occurred_at = Time.zone.iso8601(payload.fetch("occurred_at").to_s)
    id = Integer(payload.fetch("id"))
    return nil unless id.positive?

    { occurred_at: occurred_at, id: id }
  rescue ArgumentError, KeyError, JSON::ParserError
    nil
  end
end
