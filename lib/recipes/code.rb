Capistrano::Configuration.instance(:must_exist).load do
  set(:deploy_via) {application_config["deploy_strategy"] || :remote_cache}
  if deploy_via == :remote_cache
    set :scm, :git
    set :scm_verbose, true
    set(:repository) {application_config['repository'] % {:scm_username => (application_config['scm_username'] || '')}}

    if application_config["scm_username"]
      set :scm_username, application_config["scm_username"]
      set(:scm_password) { application_config["scm_password"] || Proc.new{Capistrano::CLI.password_prompt("Git password for #{scm_username}: ")} }
    end

    if application_config["local_repository"]
      set(:scm_local_repository_username) { application_config["scm_local_repository_username"] || scm_username || "" }
      set(:local_repository) { application_config["local_repository"] % {:scm_local_repository_username => scm_local_repository_username} }
    end

    set :check_tag, application_config["check_tag"].nil? ? true : !!application_config["repository"]
    set(:branch) {deploy_via == :remote_cache ? get_current_commit_describe : nil}
  elsif deploy_via == :copy
    set :repository, '.'
  end

  namespace :deploy do
    desc "[internal] Copies the result of 'git describe' to the server"
    task :copy_version_describe do
      git_describe = %x[git describe 2> /dev/null].strip
      git_describe_filepath = File.join(current_path, "config/git_describe")
      put git_describe, git_describe_filepath
    end

    desc "[internal] Fires the current git describe code to check if this deploy will succeed."
    task :check_tag do
      if deploy_via == :remote_cache
        # getting the branch to be used will fire the get_current_commit_describe,
        # which stops execution if the current tag is not allowed to be used.
        branch
      end
    end
  end

  after "deploy:update", "deploy:copy_version_describe"
  before 'deploy:cold', "deploy:check_tag"

  def get_current_commit_describe
    command = "git describe %{option} --tags 2> /dev/null"
    ENV["ALLOW_ANY_COMMIT"] ? option = "" : option = "--exact-match"
    check_tag ? option = "--always" : option = option
    git_describe_tags = %x[#{command % {:option => option}}].strip
    if git_describe_tags.empty?
      git_describe = %x[#{command % {:option => ""}}].strip
      puts "Could not find a tag here: " + git_describe
      puts "Please change to a valid, pushed tag, create and push a new one " +
        "or set the environment variable ALLOW_ANY_COMMIT then try again."
      exit(1)
    end
  end
end
