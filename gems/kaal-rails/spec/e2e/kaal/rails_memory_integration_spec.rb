# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::Rails, integration: :memory do
  include RailsIntegrationHelpers

  it 'boots the dummy app with a memory backend override' do
    KaalRailsDummyAppSupport.with_dummy_app do |app_root, env|
      output = runner_output(app_root, env.merge('KAAL_TEST_BACKEND' => 'memory'), 'puts Kaal.configuration.backend.class.name')
      expect(output.strip).to eq('Kaal::Backend::MemoryAdapter')
    end
  end
end
