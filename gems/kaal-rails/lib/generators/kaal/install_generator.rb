# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'rails/generators'

module Kaal
  module Generators
    # Installs Kaal scheduler config and Active Record migrations into a Rails app.
    class InstallGenerator < ::Rails::Generators::Base
      class_option :backend, type: :string, desc: 'sqlite, postgres, or mysql'

      def install_kaal
        results = Kaal::Rails.install!(root: destination_root, backend: selected_backend)
        scheduler_config = results.fetch(:scheduler_config)
        say_status(scheduler_config.fetch(:status), scheduler_config.fetch(:path))
        results.fetch(:migrations).each do |migration|
          say_status(migration.fetch(:status), migration.fetch(:path))
        end
      end

      private

      def selected_backend
        options[:backend] || Kaal::Rails.detect_backend_name
      end
    end
  end
end
