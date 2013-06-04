Capistrano::Configuration.instance(:must_exist).load do
  if application_config["use_nginx"]
    set :nginx_path_prefix, "/etc/nginx/"
    set :nginx_local_config, "nginx.conf.erb"
    set :nginx_remote_config, File.join(nginx_path_prefix, "sites-available/#{application}.conf")
    set :unicorn_socket, application_config["unicorn_socket"]

    namespace :deploy do
      desc "[internal] Add NGINX to dependencies"
      task :add_nginx_to_dependencies do
        optional_dependencies << "nginx"
        add_service_dependence("nginx")
      end
    end

    namespace :nginx do
      desc "Parses and uploads nginx configuration for this app."
      task :setup, :roles => :app, :except => { :no_release => true } do
        sites_available_dir = File.dirname nginx_remote_config
        sites_enabled_dir = File.expand_path(File.join(sites_available_dir, "../sites-enabled"))
        sudo "mkdir -p " + sites_available_dir
        buffer = parse_template(nginx_local_config)
        temp_filepath = "/tmp/nginx_config_temp_file"
        sites_enabled_filepath = File.join(sites_enabled_dir, File.basename(nginx_remote_config))
        begin
          put buffer, temp_filepath
          sudo "mv #{temp_filepath} #{nginx_remote_config}"
          sudo "mkdir -p " + sites_enabled_dir
          sudo "rm -f " + sites_enabled_filepath
          sudo "ln -s #{nginx_remote_config} #{sites_enabled_filepath}"
        ensure
          sudo "rm -f " + temp_filepath
        end
      end

      desc "Parses config file and outputs it to STDOUT (internal task)"
      task :parse, :roles => :app, :except => { :no_release => true } do
        puts parse_template(nginx_local_config)
      end

      desc "Restart nginx"
      task :restart, :roles => :app, :except => { :no_release => true } do
        sudo "service nginx restart"
      end

      desc "Stop nginx"
      task :stop, :roles => :app, :except => { :no_release => true } do
        sudo "service nginx stop"
      end

      desc "Start nginx"
      task :start, :roles => :app, :except => { :no_release => true } do
        sudo "service nginx start"
      end

      desc "Show nginx status"
      task :status, :roles => :app, :except => { :no_release => true } do
        sudo "service nginx status"
      end
    end

    before 'deploy:dependencies', 'deploy:add_nginx_to_dependencies'
    after 'deploy:cold', "nginx:setup", "nginx:restart"
  end
end
