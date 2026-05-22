# frozen_string_literal: true

require "json"
require "sidekiq/api"

namespace :logister do
  namespace :sidekiq do
    desc "Prune stale ClickHouse UnknownJobClass retry entries. Dry run by default; set DRY_RUN=false to delete."
    task prune_clickhouse_unknown_job_retries: :environment do
      dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "true"))
      matched = []

      Sidekiq::RetrySet.new.each do |job|
        item = job.item
        active_job_class = item.dig("args", 0, "job_class").to_s
        next unless active_job_class.in?(%w[ClickhouseIngestJob ClickhouseSpanIngestJob])
        next unless item["error_class"].to_s == "ActiveJob::UnknownJobClassError"

        matched << {
          jid: item["jid"],
          active_job_class: active_job_class,
          retry_count: item["retry_count"],
          next_retry_at: (Time.at(job.score).utc.iso8601 rescue nil),
          error_message: item["error_message"].to_s.truncate(220)
        }
        job.delete unless dry_run
      end

      puts JSON.pretty_generate(
        dry_run: dry_run,
        matched: matched.size,
        pruned: dry_run ? 0 : matched.size,
        jobs: matched.first(25)
      )
    end
  end
end
