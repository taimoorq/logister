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

ActiveRecord::Schema[8.1].define(version: 2026_02_15_081500) do
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
    t.index ["project_id"], name: "index_api_keys_on_project_id"
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_keys_on_user_id"
    t.index ["uuid"], name: "index_api_keys_on_uuid", unique: true
  end

  create_table "ingest_events", force: :cascade do |t|
    t.bigint "api_key_id", null: false
    t.jsonb "context", default: {}, null: false
    t.datetime "created_at", null: false
    t.integer "event_type", null: false
    t.string "fingerprint"
    t.string "level"
    t.text "message", null: false
    t.datetime "occurred_at", null: false
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.index ["api_key_id"], name: "index_ingest_events_on_api_key_id"
    t.index ["project_id", "event_type"], name: "index_ingest_events_on_project_id_and_event_type"
    t.index ["project_id", "occurred_at"], name: "index_ingest_events_on_project_id_and_occurred_at"
    t.index ["project_id"], name: "index_ingest_events_on_project_id"
    t.index ["uuid"], name: "index_ingest_events_on_uuid", unique: true
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
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
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "unconfirmed_email"
    t.datetime "updated_at", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["uuid"], name: "index_users_on_uuid", unique: true
  end

  add_foreign_key "api_keys", "projects"
  add_foreign_key "api_keys", "users"
  add_foreign_key "ingest_events", "api_keys"
  add_foreign_key "ingest_events", "projects"
  add_foreign_key "projects", "users"
end
