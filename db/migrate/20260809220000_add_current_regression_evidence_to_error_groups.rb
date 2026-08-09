class AddCurrentRegressionEvidenceToErrorGroups < ActiveRecord::Migration[8.0]
  def up
    add_column :error_groups, :current_regression, :jsonb, null: false, default: {}

    execute <<~SQL.squish
      UPDATE error_groups
      SET current_regression = jsonb_strip_nulls(jsonb_build_object(
        'schema_version', 1,
        'reason', 'legacy_regression',
        'policy_reason', 'legacy_regression',
        'time_precision', 'unknown',
        'detected_at', to_char(last_reopened_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'release', regressed_in_release
      ))
      WHERE regression_count > 0
        AND current_regression = '{}'::jsonb
    SQL
  end

  def down
    remove_column :error_groups, :current_regression
  end
end
