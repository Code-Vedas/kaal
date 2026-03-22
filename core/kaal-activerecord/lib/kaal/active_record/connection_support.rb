# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  module ActiveRecord
    # Establishes and reuses the Active Record connection for adapter models.
    module ConnectionSupport
      CONFIGURE_MUTEX = Mutex.new

      module_function

      def configure!(connection = nil)
        return BaseRecord unless connection

        CONFIGURE_MUTEX.synchronize do
          current_config = current_connection_config
          target_config = normalize_connection_config(connection)
          return BaseRecord if configs_match?(current_config, target_config)

          BaseRecord.establish_connection(connection)
        end
        BaseRecord
      end

      def normalize_connection_config(connection)
        config = extract_connection_config(connection)
        return connection unless config

        config.each_with_object({}) do |(key, value), normalized|
          normalized_key = key.to_sym
          normalized[normalized_key] = normalize_connection_value(normalized_key, value)
        end
      end

      def current_connection_config
        db_config = BaseRecord.connection_db_config
        normalize_connection_config(extract_connection_config(db_config))
      rescue ::ActiveRecord::ConnectionNotEstablished
        nil
      end

      def extract_connection_config(connection)
        case connection
        when Hash
          connection
        when String
          { url: connection }
        else
          config = connection.configuration_hash
          url = begin
            connection.url
          rescue NoMethodError
            nil
          end
          url ? config.merge(url: url) : config
        end
      rescue NoMethodError
        nil
      end

      def normalize_connection_value(key, value)
        case key
        when :adapter
          value.to_s.downcase
        when :port
          integer_like?(value) ? value.to_i : value
        else
          value
        end
      end

      def integer_like?(value)
        value.is_a?(Integer) || value.to_s.match?(/\A\d+\z/)
      end

      def configs_match?(current_config, target_config)
        return true if current_config == target_config

        current_url = current_config.is_a?(Hash) ? current_config[:url] : nil
        target_url = target_config.is_a?(Hash) ? target_config[:url] : nil
        !!(current_url && target_url && current_url == target_url)
      end
    end
  end
end
