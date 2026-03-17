# frozen_string_literal: true

namespace :kaal do
  namespace :install do
    desc 'Install Kaal scheduler config and Active Record migrations'
    task all: :environment do
      results = Kaal::Rails.install!
      puts "#{results.fetch(:scheduler_config).fetch(:status)} #{results.fetch(:scheduler_config).fetch(:path)}"
      results.fetch(:migrations).each do |migration|
        puts "#{migration.fetch(:status)} #{migration.fetch(:path)}"
      end
    end

    desc 'Install Kaal Active Record migrations'
    task migrations: :environment do
      installer = Kaal::Rails::Installer.new(root: Rails.root, backend: Kaal::Rails.detect_backend_name)
      installer.install_migrations.each do |migration|
        puts "#{migration.fetch(:status)} #{migration.fetch(:path)}"
      end
    end
  end
end
