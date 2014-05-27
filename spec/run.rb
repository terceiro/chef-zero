#!/usr/bin/env ruby
require 'bundler'
require 'bundler/setup'

require 'chef_zero/server'
require 'rspec/core'

tmpdir = nil

def start_server(chef_repo_path)
  Dir.mkdir(chef_repo_path) if !File.exists?(chef_repo_path)

  # 11.6 and below had a bug where it couldn't create the repo children automatically
  if Chef::VERSION.to_f < 11.8
    %w(clients cookbooks data_bags environments nodes roles users).each do |child|
      Dir.mkdir("#{chef_repo_path}/#{child}") if !File.exists?("#{chef_repo_path}/#{child}")
    end
  end

  # Start the new server
  Chef::Config.repo_mode = 'everything'
  Chef::Config.chef_repo_path = chef_repo_path
  Chef::Config.versioned_cookbooks = true
  chef_fs = Chef::ChefFS::Config.new.local_fs
  data_store = Chef::ChefFS::ChefFSDataStore.new(chef_fs)
  data_store = ChefZero::DataStore::V1ToV2Adapter.new(data_store, 'chef', :org_defaults => ChefZero::DataStore::V1ToV2Adapter::ORG_DEFAULTS)
  server = ChefZero::Server.new(:port => 8889, :data_store => data_store)#, :log_level => :debug)
  server.start_background
  server
end

begin
  if ENV['CHEF_FS']
    require 'chef/chef_fs/chef_fs_data_store'
    require 'chef/chef_fs/config'
    require 'tmpdir'
    require 'fileutils'
    require 'chef/version'
    require 'chef_zero/data_store/v1_to_v2_adapter'

    # Create chef repository
    tmpdir = Dir.mktmpdir
    chef_repo_path = "#{tmpdir}/repo"

    # Capture setup data into master_chef_repo_path
    server = start_server(chef_repo_path)

  else
    server = ChefZero::Server.new(:port => 8889)
    server.start_background
  end

  unless ENV['SKIP_PEDANT']
    require 'pedant'
    require 'pedant/opensource'

    #Pedant::Config.rerun = true

    Pedant.config.suite = 'api'
    Pedant.config[:config_file] = 'spec/support/pedant.rb'
    Pedant.setup([
      '--skip-knife',
      '--skip-validation',
      '--skip-authentication',
      '--skip-authorization',
      '--skip-omnibus'
    ])

    result = RSpec::Core::Runner.run(Pedant.config.rspec_args)
  else
    require 'net/http'
    response = Net::HTTP.new('127.0.0.1', 8889).get("/environments", { 'Accept' => 'application/json'}).body
    if response =~ /_default/
      result = 0
    else
      puts "GET /environments returned #{response}.  Expected _default!"
      result = 1
    end
  end

  server.stop if server.running?
ensure
  FileUtils.remove_entry_secure(tmpdir) if tmpdir
end

exit(result)
