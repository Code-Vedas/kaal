# frozen_string_literal: true

module Kaal
  module Support
    # Small deep-copy and key-normalization helpers used across config and scheduler loading.
    module HashTools
      module_function

      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, child), memo|
            duplicated_pair = [deep_dup(key), deep_dup(child)]
            memo[duplicated_pair[0]] = duplicated_pair[1]
          end
        when Array
          value.map { |child| duplicate_child(child) }
        else
          duplicable?(value) ? value.dup : value
        end
      end

      def stringify_keys(value)
        transform_keys(value, &:to_s)
      end

      def symbolize_keys(value)
        transform_keys(value, &:to_sym)
      end

      def deep_merge(left, right)
        left.merge(right) do |_key, left_value, right_value|
          if left_value.is_a?(Hash) && right_value.is_a?(Hash)
            deep_merge(left_value, right_value)
          else
            deep_dup(right_value)
          end
        end
      end

      def constantize(name)
        name.to_s.split('::').reject(&:empty?).reduce(Object) { |scope, part| scope.const_get(part) }
      end

      def duplicable?(value)
        !value.is_a?(NilClass) &&
          !value.is_a?(FalseClass) &&
          !value.is_a?(TrueClass) &&
          !value.is_a?(Symbol) &&
          !value.is_a?(Numeric) &&
          !value.is_a?(Method) &&
          !value.is_a?(Proc)
      end

      def transform_keys(value, &)
        case value
        when Hash
          transform_hash_keys(value, &)
        when Array
          transform_array_keys(value, &)
        else
          value
        end
      end

      def duplicate_child(child)
        deep_dup(child)
      end

      def transform_child_keys(child, &)
        transform_keys(child, &)
      end

      def transform_hash_keys(value, &)
        value.each_with_object({}) do |(key, child), memo|
          transformed_pair = [yield(key), transform_child_keys(child, &)]
          memo[transformed_pair[0]] = transformed_pair[1]
        end
      end

      def transform_array_keys(value, &)
        value.map { |child| transform_child_keys(child, &) }
      end

      private_class_method :duplicate_child, :transform_child_keys, :transform_hash_keys, :transform_array_keys
      private_class_method :transform_keys
    end
  end
end
