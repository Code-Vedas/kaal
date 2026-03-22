# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'fileutils'
require 'open3'
require 'pathname'
require 'tmpdir'
require 'uri'

module KaalRailsDummyAppSupport
  module_function

  GEM_ROOT = File.expand_path('../..', __dir__)
  DUMMY_SOURCE = File.join(GEM_ROOT, 'spec', 'dummy')

  def with_dummy_app
    Dir.mktmpdir('kaal-rails-dummy-') do |root|
      app_root = File.join(root, 'dummy')
      FileUtils.copy_entry(DUMMY_SOURCE, app_root)
      yield app_root, default_env
    end
  end

  def run!(app_root, env, *command)
    stdout, stderr, status = Open3.capture3(normalized_env(env), *command, chdir: app_root)
    return stdout if status.success?

    raise <<~ERROR
      Command failed: #{command.join(' ')}
      stdout:
      #{stdout}
      stderr:
      #{stderr}
    ERROR
  end

  def migration_slugs(app_root)
    Dir[File.join(app_root, 'db/migrate/*.rb')]
      .map { |path| File.basename(path).sub(/^\d+_/, '') }
      .sort
  end

  def reset_database!(database_url)
    uri = URI.parse(database_url)

    case uri.scheme
    when 'postgres', 'postgresql'
      reset_postgres_database!(uri)
    when 'mysql2'
      reset_mysql_database!(uri)
    else
      raise ArgumentError, "Unsupported database URL for reset: #{database_url.inspect}"
    end
  end

  def default_env
    {
      'KAAL_RAILS_LIB_PATH' => File.join(GEM_ROOT, 'lib'),
      'RAILS_ENV' => 'test'
    }
  end

  def normalized_env(env)
    merged_env = default_env.merge(env)
    bundle_gemfile = merged_env['BUNDLE_GEMFILE'] || ENV.fetch('BUNDLE_GEMFILE', nil)

    return merged_env if bundle_gemfile.to_s.empty?
    return merged_env.merge('BUNDLE_GEMFILE' => bundle_gemfile) if Pathname.new(bundle_gemfile).absolute?

    merged_env.merge('BUNDLE_GEMFILE' => File.expand_path(bundle_gemfile, GEM_ROOT))
  end

  def reset_postgres_database!(uri)
    require 'pg'

    database_name = uri.path.delete_prefix('/')
    admin_connection = PG.connect(
      host: uri.host,
      port: uri.port || 5432,
      user: uri.user,
      password: uri.password,
      dbname: 'postgres'
    )

    admin_connection.exec_params(
      'SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()',
      [database_name]
    )
    admin_connection.exec("DROP DATABASE IF EXISTS #{PG::Connection.quote_ident(database_name)}")
    admin_connection.exec("CREATE DATABASE #{PG::Connection.quote_ident(database_name)}")
  ensure
    admin_connection&.close
  end

  def reset_mysql_database!(uri)
    require 'mysql2'

    database_name = uri.path.delete_prefix('/')
    admin_connection = Mysql2::Client.new(
      host: uri.host,
      port: uri.port || 3306,
      username: uri.user,
      password: uri.password
    )

    quoted_database_name = admin_connection.escape(database_name)
    admin_connection.query("DROP DATABASE IF EXISTS `#{quoted_database_name}`")
    admin_connection.query("CREATE DATABASE `#{quoted_database_name}`")
  ensure
    admin_connection&.close
  end
end
