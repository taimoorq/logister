class CreateTraceSpans < ActiveRecord::Migration[8.1]
  def change
    create_table :trace_spans do |t|
      t.references :project, null: false, foreign_key: true
      t.references :api_key, null: false, foreign_key: true
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :trace_id, null: false
      t.string :span_id, null: false
      t.string :parent_span_id
      t.string :name, null: false
      t.string :kind, null: false, default: "internal"
      t.string :status
      t.float :duration_ms, null: false, default: 0.0
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.jsonb :context, null: false, default: {}
      t.timestamps
    end

    add_index :trace_spans, :uuid, unique: true
    add_index :trace_spans, [ :project_id, :started_at ], order: { started_at: :desc }
    add_index :trace_spans, [ :project_id, :kind, :started_at ], order: { started_at: :desc }
    add_index :trace_spans, [ :project_id, :trace_id, :started_at ], order: { started_at: :desc }
    add_index :trace_spans, [ :project_id, :trace_id, :span_id ], unique: true
    add_index :trace_spans, [ :project_id, :trace_id, :parent_span_id ], name: "idx_trace_spans_trace_parent"
    add_index :trace_spans, :context, using: :gin, opclass: :jsonb_path_ops
  end
end
