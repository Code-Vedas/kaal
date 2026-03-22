# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'rails/railtie'

module Kaal
  module Rails
    # Railtie that wires Kaal into a Rails app.
    class Railtie < ::Rails::Railtie
      initializer 'kaal-rails.configure_backend', after: 'active_record.initialize_database' do
        Kaal::Rails.configure_backend!
      end

      rake_tasks do
        load File.expand_path('../../tasks/kaal/rails_tasks.rake', __dir__)
      end
    end
  end
end
