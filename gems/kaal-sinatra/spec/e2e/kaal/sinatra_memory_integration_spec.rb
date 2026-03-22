# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Kaal::Sinatra, integration: :memory do
  include SinatraIntegrationHelpers

  it 'integrates a classic Sinatra app through the memory backend' do
    run_dummy_app(:classic, backend: 'memory', app_class_name: 'Sinatra::Application') do |app_root, _env, lines|
      expect(lines).to eq(['200', 'Kaal::Backend::MemoryAdapter', 'true'])
      expect(File.read(KaalSinatraDummyAppSupport.job_log_path(app_root))).not_to be_empty
    end
  end

  it 'integrates a modular Sinatra app through the memory backend' do
    run_dummy_app(:modular, backend: 'memory', app_class_name: 'ModularDummyApp') do |app_root, _env, lines|
      expect(lines).to eq(['200', 'Kaal::Backend::MemoryAdapter', 'true'])
      expect(File.read(KaalSinatraDummyAppSupport.job_log_path(app_root))).not_to be_empty
    end
  end
end
