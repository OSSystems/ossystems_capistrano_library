Capistrano::Configuration.instance(:must_exist).load do
  set :initd_template, "init.d.erb"
  set :initd_path_prefix, "/etc/init.d/"
  set :initd_remote_config, File.join(initd_path_prefix, application)
  set(:application_human_name) {application_config["human_name"]}
  set(:description) {application_config["description"]}
  set(:short_description) {application_config["short_description"]}
  set :additional_required_start, []
  set :additional_required_stop, []

  namespace :deploy do
    desc "Creates an init.d script for the application."
    task :add_initd_script do
      buffer = parse_template(initd_template)
      temp_filepath = "/tmp/#{application}_initd_temp_file"
      put buffer, temp_filepath
      sudo "update-rc.d #{application} remove"
      sudo "mv #{temp_filepath} #{initd_remote_config}"
      sudo "chmod +x " + initd_remote_config
      sudo "update-rc.d #{application} defaults"
    end
  end

  after "deploy:first_code_deployed", "deploy:add_initd_script"

  def add_service_dependence(new_dependence)
    additional_required_start << new_dependence
    additional_required_stop << new_dependence
  end
end
