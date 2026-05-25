# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'
Kaal::ActiveRecord.require_activerecord!
require 'kaal/internal/active_record'

RSpec.describe Kaal::ActiveRecord, integration: :sqlite do
  it 'supports sqlite-backed scheduling through the documented plain-ruby API' do
    key = 'integration:sqlite'
    namespace = KaalIntegrationSupport.namespace('activerecord-sqlite')
    fixed_time = Time.utc(2026, 1, 1, 0, 0, 30)
    allow(Time).to receive(:now).and_return(*Array.new(100, fixed_time))

    KaalIntegrationSupport.with_project_root('activerecord-sqlite') do |root|
      db_dir = File.join(root, 'db')
      db_path = File.join(db_dir, 'kaal.sqlite3')
      FileUtils.mkdir_p(db_dir)
      described_class.require_activerecord!
      Kaal::Internal::ActiveRecord::ConnectionSupport.configure!(adapter: 'sqlite3', database: db_path)
      KaalActiveRecordSupport.create_schema!(locks: true)

      KaalIntegrationSupport.write_scheduler(root, key:)
      KaalIntegrationSupport.write_runtime_config(
        root,
        backend: :sqlite,
        namespace:,
        backend_config: {
          connection: {
            adapter: 'sqlite3',
            database: 'db/kaal.sqlite3'
          }
        }
      )

      job_calls = KaalIntegrationSupport.perform_tick_flow(root, key:)

      expect(Kaal.backend).to be_a(Kaal::Backend::SQLite)
      expect(Kaal::Internal::ActiveRecord::DefinitionRecord.count).to eq(1)
      expect(Kaal::Internal::ActiveRecord::DispatchRecord.count).to eq(job_calls.length)
      expect(Kaal::Internal::ActiveRecord::LockRecord.count).to eq(job_calls.length)
    end
  end
end
