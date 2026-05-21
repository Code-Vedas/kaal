# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'kaal/scheduler_file/loader'
require 'kaal/scheduler_file/hash_transform'
require 'kaal/scheduler_file/placeholder_support'

module Kaal
  # Scheduler file loading and payload helpers.
  module SchedulerFile
    Loader = ::Kaal::SchedulerFileLoader
    HashTransform = ::Kaal::SchedulerHashTransform
    PlaceholderSupport = ::Kaal::SchedulerPlaceholderSupport
  end
end
