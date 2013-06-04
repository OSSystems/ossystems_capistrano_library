require 'yaml'
require 'tempfile'
require 'bundler/capistrano'

Capistrano::Configuration.instance(:must_exist).load do
  load 'deploy'

  DEFAULT_DEPENDENCIES = ["autoconf",
                          "automake",
                          "bison",
                          "build-essential",
                          "curl",
                          "gawk",
                          "git-core",
                          "libffi-dev",
                          "libgdbm-dev",
                          "libncurses5-dev",
                          "libpq-dev",
                          "libreadline6-dev",
                          "libsqlite3-dev",
                          "libssl-dev",
                          "libtool",
                          "libxml2-dev",
                          "libxslt1-dev",
                          "libyaml-dev",
                          "pkg-config",
                          "sqlite3",
                          "zlib1g-dev"]

  configs_path = File.join(Dir.pwd, 'config/deploy/*.yml')
  config_filepaths = Dir[configs_path].sort

  def select_deployment_site(config_filepaths, configs_path)
    configs = []
    config_filepaths.each do |config_filepath|
      configs << YAML::load_file(config_filepath)
    end

    if configs.empty? or configs.size < 1
      path = File.dirname(configs_path)
      puts "No valid deployment site options in " + path + ".\n" +
        "Use the sample file provided in the same directory to create a " +
        "valid file."
      exit(1)
    end

    if configs.size == 1
      input_index = 1
    else
      input_index = nil
    end

    while input_index.nil? or input_index > configs.size or input_index < 1
      puts "Invalid deployment site number.\n\n" unless input_index.nil?

      puts "Select the deployment site you want to work on:"
      configs.each_with_index do |config, index|
        puts "  " + (index + 1).to_s + ". " + config["deploy_name"]
      end
      puts ""
      print "Deployment site: "
      input_index = $stdin.gets.to_i
    end

    selected_config = configs[input_index - 1]
    deploy_name = selected_config["deploy_name"]
    puts "Selected deployment site \"" + deploy_name + "\"."
    config_filepaths[input_index - 1]
  end

  if not ENV["CONFIG_FILE"].nil?
    application_config_file_path = ENV["CONFIG_FILE"]
  elsif config_filepaths.size > 0
    application_config_file_path = select_deployment_site(config_filepaths, configs_path)
  else
    application_config_file_path = File.join(Dir.pwd, 'config/basic_config.yml')
  end

  if File.exists? application_config_file_path
    set :application_config, YAML::load( File.read application_config_file_path )
  end

  if application_config.nil? || application_config.empty?
    raise Capistrano::CommandError.new <<-END
      Config file does not exist! Add a new config file or pass the config
      file path via CONFIG_FILE environment variable and then try again.
    END
  end

  # Deployment credentials and environment:
  set :application, application_config["name"]
  set :application_user, application_config["user"]
  set :application_port, application_config["port"] || 80
  set :set_default_deploy_actions, application_config["set_default_deploy_actions"].nil? ? true : application_config["set_default_deploy_actions"]
  set :deploy_to, File.join("/srv/", application)
  set :rails_env, "production"
  set :templates_path, File.expand_path(__FILE__ + "/../templates")
  set(:override_templates_path) { application_config["orverride_templates_dir"] }
  set :optional_dependencies, Array(application_config["optional_dependencies"])

  set :tmp_sockets, "tmp/sockets"

  # SSH:
  default_run_options[:pty] = true
  ssh_options[:forward_agent] = true
  # comment out the next line if it gives you trouble. newest net/ssh needs this
  # set.
  ssh_options[:paranoid] = true

  if set_default_deploy_actions
    # Add a few directories to be shared between releases:
    shared_children.push File.dirname(application_config["secret_token_file"])
    shared_children.push tmp_sockets
  end

  # Hooks
  before 'deploy:setup', "deploy:dependencies"
  after "deploy:update", "deploy:fix_permissions"
  after "deploy:update", "deploy:copy_basic_config_file"
  after "deploy:update", "deploy:cleanup"
  after "deploy:update", "deploy:update_mo_files"

  # Custom tasks
  namespace :deploy do
    desc "Stop processes that bluepill is monitoring and quit bluepill"
    task :stop, :roles => [:app] do
      rvmsudo "bluepill #{application} stop" # stop the processes
      rvmsudo "bluepill #{application} quit" # stop monitoring
    end

    desc "Load bluepill configuration and start it"
    task :start, :roles => [:app] do
      rvmsudo "bluepill load config/#{application}.pill"
    end

    desc "Stop bluepill and all processes and restart everything"
    task :restart, :roles => [:app] do
      deploy.stop
      deploy.start
    end

    desc "bluepills monitored processes statuses"
    task :status, :roles => [:app] do
      rvmsudo "bluepill #{application} status"
    end

    desc "Installs all the application dependencies"
    task :dependencies do
      sudo "apt-get -qyu --force-yes update; true", :shell => "bash"
      dependencies = DEFAULT_DEPENDENCIES
      dependencies += optional_dependencies
      sudo "apt-get -qyu --force-yes install #{dependencies.join(" ")}", :shell => "bash"
    end

    desc "Creates the user that will be used by the application"
    task :add_user do
      status = get_return_status("id -u #{application_user} >/dev/null 2>&1")
      if status != 0 # return status != 0 => user does not exist
        sudo "useradd --system --shell /bin/false #{application_user}"
      else
        puts "User '#{application_user}' already exists. Ignoring..."
      end
    end

    desc "Corrects the deployment user permissions in the application path"
    task :fix_permissions do
      log_file_path = File.join(shared_path, "log/#{rails_env}.log")
      sudo "touch " + log_file_path
      sudo "chown -R #{user}:#{application_user} " + deploy_to
      sudo "chmod -R g-w " + deploy_to
      sudo "chmod -R g+w " + File.join(shared_path, "log")
      sudo "chmod -R g+w " + File.join(shared_path, "pids")
      if shared_children.include? tmp_sockets
        sudo "chmod -R g+w " + File.join(shared_path, "sockets")
      end
    end

    desc "Deploys and starts a `cold' application."
    task :cold do
      deploy.setup
      deploy.add_user
      deploy.fix_permissions
      deploy.update
      deploy.generate_secret_token if set_default_deploy_actions
      deploy.first_code_deployed
      deploy.start
    end

    desc "Copies the basic config file to the server."
    task :copy_basic_config_file do
      config_buffer = application_config.to_yaml
      config_filepath = File.join(current_path, "config/basic_config.yml")
      put config_buffer, config_filepath
    end

    desc "Generate a file containing the application secret token."
    task :generate_secret_token do
      filepath = application_config["secret_token_file"]
      shared_dir = File.join(File.basename(File.dirname(filepath)), File.basename(filepath))
      filepath = File.join(shared_path, shared_dir)
      rvmsudo "rake secret > " + filepath
    end

    desc <<-EOF
      [internal] Utility task to allow other tasks to execute after the first
      deploy is finished.
    EOF
    task :first_code_deployed do
      # nothing to do...
    end

    desc "Updates the Gettext mo files."
    task :update_mo_files do
      if application_config["use_gettext_as_i18n"]
        rvmsudo "rake gettext:pack"
      end
    end
  end

  def get_return_status(command)
    status = nil
    run "#{command}; echo return code: $?" do |channel, stream, data|
      if data =~ /return code: (\d+)/
        status = $1.to_i
      else
        Capistrano::Configuration.default_io_proc.call(channel, stream, data)
      end
    end
    return status
  end

  def parse_template(file)
    template_path = nil
    if override_templates_path
      template_path = File.join(override_templates_path, file)
    end
    if template_path.nil? or not File.exists?(template_path)
      template_path = File.join(templates_path, file)
    end
    require 'erb'
    template = File.read(template_path)
    return ERB.new(template).result(binding)
  end

  def ask_info(message, invalid_data_message, valid_options=[], only_option_message="Autoselected only option")
    if valid_options.size == 1
      message ||= only_option_message
      puts message + ": #{valid_options.first}"
      return valid_options.first
    end

    input = nil
    valid_options_messages = []
    valid_options.each_with_index do |option, i|
      valid_options_messages << "  #{(i+1).to_s}. #{option}"
    end
    valid_options_messages = valid_options_messages.join("\n")

    while input.nil? or input.empty?
      if not valid_options.empty? and valid_options.include?(input)
        break
      end

      if not valid_options.empty?
        puts message
        puts valid_options_messages
        print "Select one: "
      else
        print message
      end

      input = $stdin.gets.strip
      if input.empty? or (not valid_options.empty? and (input.to_i > valid_options.size or input.to_i < 1))
        puts invalid_data_message
        input = nil
      end
    end

    if not valid_options.empty?
      input = valid_options[input.to_i-1]
    end

    return input
  end

  def set_server_info
    message = "Server hostname/address: "
    invalid_message = "Invalid server hostname/address."
    server ENV["SERVER"] || application_config["server"] || ask_info(message, invalid_message), :web,  :app, :db, :primary => true

    message = "Server username with sudo or root: "
    invalid_message = "Invalid server username.\n\n"
    set :user, ENV["SERVER_USERNAME"] || application_config["deploy_user"] || ask_info(message, invalid_message)

    return
  end
  set_server_info

  require "recipes/rvm"
  require "recipes/git"
  require "recipes/init.d"
  require "recipes/database"
  require "recipes/nginx"
end
