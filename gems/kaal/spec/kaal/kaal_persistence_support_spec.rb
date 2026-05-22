# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal do
  describe Kaal::Sequel do
    it 'installs sequel migrations for sqlite and postgres' do
      Dir.mktmpdir do |dir|
        paths = described_class.install_migrations(
          target_dir: dir,
          backend: 'sqlite',
          migration_name: 'Create Delayed Jobs'
        )
        expect(paths.map { |path| File.basename(path) }).to all(include('create_delayed_jobs'))
        expect(paths.length).to eq(4)
      end

      expect(described_class.send(:migration_suffixes_for, 'postgres')).to eq(%w[dispatches definitions delayed_jobs])
      expect(described_class.send(:normalize_migration_name, 'Create Delayed Jobs', fallback: 'fallback')).to eq('create_delayed_jobs')
      expect(described_class.send(:normalize_migration_name, '!!!', fallback: 'fallback')).to eq('fallback')
      expect(described_class.send(:default_migration_name_for, 'mysql')).to eq('create_kaal_mysql_backend')
      expect(described_class.send(:letter?, 'a')).to be(true)
      expect(described_class.send(:digit?, '1')).to be(true)
    end
  end

  describe Kaal::ActiveRecord do
    it 'installs active record migrations for sqlite and mysql' do
      require 'kaal/internal/active_record/migration_templates'

      Dir.mktmpdir do |dir|
        paths = described_class.install_migrations(
          target_dir: dir,
          backend: 'sqlite',
          migration_name: 'Create Delayed Jobs',
          time_source: -> { Time.utc(2026, 1, 1, 0, 0, 0) }
        )
        expect(paths.map { |path| File.basename(path) }).to all(include('create_delayed_jobs'))
        expect(paths.length).to eq(4)
      end

      expect(described_class.send(:migration_suffixes_for, 'mysql')).to eq(%w[dispatches definitions delayed_jobs])
      expect(described_class.send(:normalize_migration_name, 'Create Delayed Jobs', fallback: 'Fallback')).to eq('CreateDelayedJobs')
      expect(described_class.send(:normalize_migration_name, '!!!', fallback: 'Fallback')).to eq('Fallback')
      expect(described_class.send(:default_migration_class_for, 'postgres')).to eq('CreateKaalPostgresBackend')
      expect(described_class.send(:alphanumeric?, 'a')).to be(true)
      expect(described_class.send(:alphanumeric?, '-')).to be(false)
    end
  end
end
