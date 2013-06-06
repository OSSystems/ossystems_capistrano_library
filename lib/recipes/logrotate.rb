Capistrano::Configuration.instance(:must_exist).load do
  set :logrotate_template, "logrotate.erb"
  set :logrotate_dir_path, "/etc/logrotate.d/"
  set :log_path_glob, File.join(shared_path, "/log/*.log")

  namespace :deploy do
    desc "Creates a logrotate script for the application."
    task :add_logrotate_script do
      buffer = parse_template(logrotate_template)
      remote_logrotate_script_path = File.join(logrotate_dir_path, application)
      temp_filepath = "/tmp/#{application}_logrotate_temp_file"
      begin
        put buffer, temp_filepath
        sudo "chown -R root:root " + temp_filepath
        sudo "mv #{temp_filepath} #{remote_logrotate_script_path}"
      ensure
        sudo "rm -f " + temp_filepath
      end
    end
  end

  after "deploy:first_code_deployed", "deploy:add_logrotate_script"
end
