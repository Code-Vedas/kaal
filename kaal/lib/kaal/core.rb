# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'kaal/core/coordinator'
require 'kaal/core/occurrence_finder'
require 'kaal/core/enabled_entry_enumerator'

module Kaal
  # Core scheduling orchestration types.
  module Core
    Coordinator = ::Kaal::Coordinator
    OccurrenceFinder = ::Kaal::OccurrenceFinder
    EnabledEntryEnumerator = ::Kaal::EnabledEntryEnumerator
  end
end
