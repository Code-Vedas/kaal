# frozen_string_literal: true

require 'rails/railtie'

module Kaal
  module ActiveRecord
    # Minimal Railtie so the adapter can integrate with Rails loading.
    class Railtie < ::Rails::Railtie
    end
  end
end
