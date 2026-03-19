# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'
require 'open3'
require 'rbconfig'

RSpec.describe Kaal::SchedulerHashTransform do
  it 'delegates stringify and symbolize helpers through the mixin' do
    host = Class.new do
      include Kaal::SchedulerHashTransform

      def call(value)
        [stringify_keys(value), symbolize_keys_deep(value)]
      end
    end.new

    stringified, symbolized = host.call(a: { b: 1 })
    expect(stringified).to eq('a' => { 'b' => 1 })
    expect(symbolized).to eq(a: { b: 1 })
  end

  it 'can be required directly without depending on broader load order' do
    lib_path = File.expand_path('../../lib', __dir__)
    stdout, stderr, status = Open3.capture3(
      { 'RUBYOPT' => nil },
      RbConfig.ruby,
      '-I',
      lib_path,
      '-e',
      <<~RUBY
        require 'kaal/scheduler_file/hash_transform'

        host = Class.new do
          include Kaal::SchedulerHashTransform

          def call(value)
            stringify_keys(value)
          end
        end

        print host.new.call(a: 1)
      RUBY
    )

    expect(status.success?).to be(true), stderr
    expect(stdout.strip).to eq('{"a" => 1}')
  end
end
