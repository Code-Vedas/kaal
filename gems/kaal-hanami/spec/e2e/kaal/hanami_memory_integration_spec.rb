# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::Hanami, integration: :memory do
  include HanamiIntegrationHelpers

  it 'integrates a Hanami app through the memory backend' do
    run_dummy_app(backend: 'memory') do |app_root, _env, lines|
      expect(lines).to eq(['200', 'Kaal::Backend::MemoryAdapter', 'true'])
      expect(File.read(KaalHanamiDummyAppSupport.job_log_path(app_root))).not_to be_empty
    end
  end
end
