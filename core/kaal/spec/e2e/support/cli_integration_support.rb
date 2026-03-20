# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'open3'
require 'timeout'

module KaalCliIntegrationSupport
  module_function

  GEM_ROOT = File.expand_path('../../..', __dir__)
  EXECUTABLE = File.join(GEM_ROOT, 'exe', 'kaal')

  def run!(*args, env: {})
    stdout, stderr, status = Open3.capture3(env, EXECUTABLE, *args, chdir: GEM_ROOT)
    return stdout if status.success?

    raise <<~ERROR
      Command failed: #{([EXECUTABLE] + args).join(' ')}
      stdout:
      #{stdout}
      stderr:
      #{stderr}
    ERROR
  end

  def start!(*, env: {})
    stdin, output, wait_thread = Open3.popen2e(env, EXECUTABLE, *, chdir: GEM_ROOT)
    stdin.close
    [output, wait_thread]
  end

  def wait_for_output(output, pattern, timeout: 10)
    buffer = +''

    Timeout.timeout(timeout) do
      loop do
        chunk = output.readpartial(1024)
        buffer << chunk
        return buffer if buffer.match?(pattern)
      end
    end
  rescue EOFError
    buffer
  end
end
