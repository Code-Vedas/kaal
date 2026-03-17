# frozen_string_literal: true

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
