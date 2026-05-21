# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'pathname'

module Kaal
  # Resolves environment and path information for plain-Ruby runtime loading.
  class RuntimeContext
    DEFAULT_ENVIRONMENT_NAME = 'development'
    ENVIRONMENT_KEYS = %w[KAAL_ENV RAILS_ENV APP_ENV RACK_ENV].freeze

    attr_reader :environment_name, :root_path

    def self.default(env: ENV, root_path: Dir.pwd)
      new(root_path: root_path, environment_name: environment_name_from(env))
    end

    def self.environment_name_from(env)
      ENVIRONMENT_KEYS.each do |key|
        value = env[key].to_s.strip
        return value unless value.empty?
      end

      DEFAULT_ENVIRONMENT_NAME
    end

    def initialize(root_path:, environment_name:)
      @root_path = Pathname.new(root_path)
      @environment_name = environment_name.to_s
    end

    def resolve_path(path)
      return path.to_s if Pathname.new(path).absolute?

      root_path.join(path).to_s
    end
  end
end
