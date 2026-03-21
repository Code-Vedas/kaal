# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'fileutils'
require 'pathname'

module Kaal
  module Rails
    # Installs scheduler config and Active Record migrations into a Rails app.
    class Installer
      SCHEDULER_TEMPLATE = <<~YAML
        defaults:
          jobs:
            - key: "example:heartbeat"
              cron: "*/5 * * * *"
              job_class: "ExampleHeartbeatJob"
              enabled: true
              args:
                - "{{fire_time.iso8601}}"
              kwargs:
                idempotency_key: "{{idempotency_key}}"
      YAML

      def initialize(root:, backend:, time_source: -> { Time.now.utc })
        @root = Pathname(root)
        @backend = validate_backend(backend.to_s)
        @time_source = time_source
      end

      def install_scheduler_config
        ensure_scheduler_config_dir
        return { status: :exists, path: scheduler_config_path_string } if scheduler_config_exists?

        File.write(scheduler_config_path, SCHEDULER_TEMPLATE)
        { status: :create, path: scheduler_config_path_string }
      end

      def install_migrations
        migrations_dir = root.join('db', 'migrate')
        FileUtils.mkdir_p(migrations_dir)

        Kaal::ActiveRecord::MigrationTemplates.for_backend(backend).map.with_index do |(name, contents), index|
          slug = name.sub(/^\d+_/, '')
          existing = Dir[migrations_dir.join("*_#{slug}").to_s].first
          next({ status: :exists, path: existing.to_s }) if existing

          target = migrations_dir.join("#{timestamp_for(index)}_#{slug}")
          File.write(target, contents)
          { status: :create, path: target.to_s }
        end
      end

      private

      attr_reader :backend, :root, :time_source

      def validate_backend(backend_name)
        if backend_name.strip.empty?
          raise ArgumentError,
                'Could not detect backend from ActiveRecord adapter; pass --backend (sqlite/postgres/mysql)'
        end

        return backend_name if %w[sqlite postgres mysql].include?(backend_name)

        raise ArgumentError, "Unsupported Rails datastore backend: #{backend_name.inspect}"
      end

      def timestamp_for(index)
        (time_source.call + index).strftime('%Y%m%d%H%M%S')
      end

      def scheduler_config_path
        root.join('config', 'scheduler.yml')
      end

      def scheduler_config_exists?
        scheduler_config_path.exist?
      end

      def scheduler_config_path_string
        scheduler_config_path.to_s
      end

      def ensure_scheduler_config_dir
        FileUtils.mkdir_p(scheduler_config_path.dirname)
      end
    end
  end
end
