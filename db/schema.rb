# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_21_185034) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "api_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.bigint "project_id", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.index ["last_used_at"], name: "index_api_keys_on_last_used_at"
    t.index ["project_id"], name: "index_api_keys_on_project_id"
    t.index ["revoked_at"], name: "index_api_keys_on_revoked_at"
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_keys_on_user_id"
    t.index ["uuid"], name: "index_api_keys_on_uuid", unique: true
  end

  create_table "check_in_monitors", force: :cascade do |t|
    t.integer "consecutive_missed_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "environment", default: "production", null: false
    t.integer "expected_interval_seconds", default: 300, null: false
    t.datetime "last_check_in_at"
    t.datetime "last_error_at"
    t.bigint "last_event_id"
    t.string "last_status", default: "ok", null: false
    t.bigint "project_id", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["last_error_at"], name: "index_check_in_monitors_on_last_error_at"
    t.index ["last_event_id"], name: "index_check_in_monitors_on_last_event_id"
    t.index ["project_id", "last_check_in_at"], name: "index_check_in_monitors_on_project_id_and_last_check_in_at"
    t.index ["project_id", "slug", "environment"], name: "idx_check_in_monitors_uniqueness", unique: true
    t.index ["project_id"], name: "index_check_in_monitors_on_project_id"
  end

  create_table "error_groups", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.string "fingerprint", null: false
    t.datetime "first_seen_at"
    t.datetime "ignored_at"
    t.string "introduced_in_release"
    t.datetime "last_reopened_at"
    t.datetime "last_seen_at"
    t.string "last_seen_release"
    t.bigint "latest_event_id"
    t.integer "occurrence_count", default: 0, null: false
    t.bigint "project_id", null: false
    t.string "regressed_in_release"
    t.integer "regression_count", default: 0, null: false
    t.integer "reopen_count", default: 0, null: false
    t.datetime "resolved_at"
    t.string "resolved_in_release"
    t.string "severity", default: "error", null: false
    t.string "stage", default: "production", null: false
    t.integer "status", default: 0, null: false
    t.string "subtitle"
    t.string "title", default: "", null: false
    t.datetime "updated_at", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.index ["archived_at"], name: "index_error_groups_on_archived_at"
    t.index ["ignored_at"], name: "index_error_groups_on_ignored_at"
    t.index ["last_reopened_at"], name: "index_error_groups_on_last_reopened_at"
    t.index ["latest_event_id"], name: "index_error_groups_on_latest_event_id"
    t.index ["project_id", "fingerprint"], name: "index_error_groups_on_project_id_and_fingerprint", unique: true
    t.index ["project_id", "first_seen_at"], name: "index_error_groups_on_project_id_and_first_seen_at"
    t.index ["project_id", "introduced_in_release"], name: "index_error_groups_on_project_id_and_introduced_in_release"
    t.index ["project_id", "last_seen_at"], name: "index_error_groups_on_project_id_and_last_seen_at"
    t.index ["project_id", "regressed_in_release"], name: "index_error_groups_on_project_id_and_regressed_in_release"
    t.index ["project_id", "status"], name: "index_error_groups_on_project_id_and_status"
    t.index ["project_id"], name: "index_error_groups_on_project_id"
    t.index ["resolved_at"], name: "index_error_groups_on_resolved_at"
    t.index ["uuid"], name: "index_error_groups_on_uuid", unique: true
  end

  create_table "error_occurrences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "error_group_id", null: false
    t.bigint "ingest_event_id", null: false
    t.datetime "occurred_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.index ["error_group_id", "ingest_event_id"], name: "index_error_occurrences_on_error_group_id_and_ingest_event_id", unique: true
    t.index ["error_group_id", "occurred_at"], name: "index_error_occurrences_on_error_group_id_and_occurred_at"
    t.index ["error_group_id"], name: "index_error_occurrences_on_error_group_id"
    t.index ["ingest_event_id"], name: "index_error_occurrences_on_ingest_event_id"
    t.index ["uuid"], name: "index_error_occurrences_on_uuid", unique: true
  end

  create_table "ingest_events", force: :cascade do |t|
    t.bigint "api_key_id", null: false
    t.jsonb "context", default: {}, null: false
    t.datetime "created_at", null: false
    t.bigint "error_group_id"
    t.integer "event_type", null: false
    t.string "fingerprint"
    t.string "level"
    t.text "message", null: false
    t.datetime "occurred_at", null: false
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.index ["api_key_id"], name: "index_ingest_events_on_api_key_id"
    t.index ["error_group_id"], name: "index_ingest_events_on_error_group_id"
    t.index ["project_id", "event_type"], name: "index_ingest_events_on_project_id_and_event_type"
    t.index ["project_id", "occurred_at"], name: "index_ingest_events_on_project_id_and_occurred_at"
    t.index ["project_id"], name: "index_ingest_events_on_project_id"
    t.index ["uuid"], name: "index_ingest_events_on_uuid", unique: true
  end

  create_table "project_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "project_id", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.index ["project_id", "user_id"], name: "index_project_memberships_on_project_id_and_user_id", unique: true
    t.index ["project_id"], name: "index_project_memberships_on_project_id"
    t.index ["user_id"], name: "index_project_memberships_on_user_id"
    t.index ["uuid"], name: "index_project_memberships_on_uuid", unique: true
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "integration_kind", default: "ruby", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.index ["integration_kind"], name: "index_projects_on_integration_kind"
    t.index ["user_id", "slug"], name: "index_projects_on_user_id_and_slug", unique: true
    t.index ["user_id"], name: "index_projects_on_user_id"
    t.index ["uuid"], name: "index_projects_on_uuid", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "unconfirmed_email"
    t.datetime "updated_at", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.index ["confirmation_sent_at"], name: "index_users_on_confirmation_sent_at"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["confirmed_at"], name: "index_users_on_confirmed_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["remember_created_at"], name: "index_users_on_remember_created_at"
    t.index ["reset_password_sent_at"], name: "index_users_on_reset_password_sent_at"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["uuid"], name: "index_users_on_uuid", unique: true
  end

  add_foreign_key "api_keys", "projects"
  add_foreign_key "api_keys", "users"
  add_foreign_key "check_in_monitors", "ingest_events", column: "last_event_id"
  add_foreign_key "check_in_monitors", "projects"
  add_foreign_key "error_groups", "ingest_events", column: "latest_event_id"
  add_foreign_key "error_groups", "projects"
  add_foreign_key "error_occurrences", "error_groups"
  add_foreign_key "error_occurrences", "ingest_events"
  add_foreign_key "ingest_events", "api_keys"
  add_foreign_key "ingest_events", "error_groups"
  add_foreign_key "ingest_events", "projects"
  add_foreign_key "project_memberships", "projects"
  add_foreign_key "project_memberships", "users"
  add_foreign_key "projects", "users"
end
