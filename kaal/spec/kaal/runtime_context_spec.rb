# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'
require 'pathname'

RSpec.describe Kaal::RuntimeContext do
  describe '.default' do
    it 'uses the first configured environment variable' do
      context = described_class.default(
        env: { 'RACK_ENV' => 'staging', 'APP_ENV' => 'production' },
        root_path: '/srv/app'
      )

      expect(context.environment_name).to eq('staging')
      expect(context.root_path).to eq(Pathname.new('/srv/app'))
    end

    it 'falls back to development when no environment variables are set' do
      context = described_class.default(env: {}, root_path: '/srv/app')

      expect(context.environment_name).to eq('development')
    end
  end

  describe '.from_rails' do
    it 'builds a runtime context from a rails-like object' do
      rails_context = Struct.new(:env, :root).new('test', Pathname.new('/app'))

      context = described_class.from_rails(rails_context)

      expect(context.environment_name).to eq('test')
      expect(context.root_path).to eq(Pathname.new('/app'))
    end
  end

  describe '#resolve_path' do
    it 'resolves relative paths against the runtime root' do
      context = described_class.new(root_path: '/app', environment_name: 'test')

      expect(context.resolve_path('config/scheduler.yml')).to eq('/app/config/scheduler.yml')
    end

    it 'returns absolute paths unchanged' do
      context = described_class.new(root_path: '/app', environment_name: 'test')

      expect(context.resolve_path('/tmp/scheduler.yml')).to eq('/tmp/scheduler.yml')
    end
  end
end
