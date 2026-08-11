# frozen_string_literal: true

class ProjectArchiveObjectCatalog
  PAGE_SIZE = 20

  Page = Data.define(:object_keys, :total, :page, :total_pages) do
    def previous_page
      page - 1 if page > 1
    end

    def next_page
      page + 1 if page < total_pages
    end
  end

  def initialize(archives:, selected_archive_id: nil, requested_page: nil)
    @archives = Array(archives)
    @selected_archive_id = Integer(selected_archive_id, exception: false)
    @requested_page = [ Integer(requested_page, exception: false).to_i, 1 ].max
  end

  def call
    v2_archives, legacy_archives = archives.partition { |archive| archive.manifest_version.to_i >= 2 }
    pages = v2_pages(v2_archives)
    legacy_archives.each { |archive| pages[archive.id] = legacy_page(archive) }
    pages
  end

  private

  attr_reader :archives, :selected_archive_id, :requested_page

  def v2_pages(v2_archives)
    archive_ids = v2_archives.map(&:id)
    return {} if archive_ids.empty?

    counts = TelemetryArchiveObject.where(telemetry_archive_id: archive_ids).group(:telemetry_archive_id).count
    selected_id = selected_archive_id if selected_archive_id.in?(archive_ids)
    selected_page = bounded_page(counts.fetch(selected_id, 0)) if selected_id
    records = ranked_records(archive_ids, selected_id:, selected_page:).group_by(&:telemetry_archive_id)

    v2_archives.to_h do |archive|
      total = counts.fetch(archive.id, 0)
      page = archive.id == selected_id ? selected_page : 1
      keys = records.fetch(archive.id, []).sort_by { |record| record["catalog_position"].to_i }.map(&:object_key)
      [ archive.id, page_data(keys:, total:, page:) ]
    end
  end

  def ranked_records(archive_ids, selected_id:, selected_page:)
    ranked = TelemetryArchiveObject
      .where(telemetry_archive_id: archive_ids)
      .select(
        "telemetry_archive_objects.*",
        "ROW_NUMBER() OVER (PARTITION BY telemetry_archive_id ORDER BY sequence, id) AS catalog_position"
      )
    scope = TelemetryArchiveObject.from("(#{ranked.to_sql}) telemetry_archive_objects")

    if selected_id
      first = ((selected_page - 1) * PAGE_SIZE) + 1
      last = selected_page * PAGE_SIZE
      scope = scope.where(
        "(telemetry_archive_id = :selected_id AND catalog_position BETWEEN :first AND :last) " \
        "OR (telemetry_archive_id <> :selected_id AND catalog_position <= :page_size)",
        selected_id: selected_id,
        first: first,
        last: last,
        page_size: PAGE_SIZE
      )
    else
      scope = scope.where("catalog_position <= ?", PAGE_SIZE)
    end

    scope.order(:telemetry_archive_id, Arel.sql("catalog_position")).to_a
  end

  def legacy_page(archive)
    keys = archive.archive_objects.filter_map do |object|
      next unless object.respond_to?(:[])

      object["key"].presence || object[:key].presence
    end
    page = archive.id == selected_archive_id ? bounded_page(keys.size) : 1
    offset = (page - 1) * PAGE_SIZE
    page_data(keys: keys.slice(offset, PAGE_SIZE).to_a, total: keys.size, page: page)
  end

  def bounded_page(total)
    [ requested_page, total_pages(total) ].min
  end

  def page_data(keys:, total:, page:)
    Page.new(object_keys: keys, total: total, page: page, total_pages: total_pages(total))
  end

  def total_pages(total)
    [ (total.to_f / PAGE_SIZE).ceil, 1 ].max
  end
end
