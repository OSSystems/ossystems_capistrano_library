lib = File.expand_path('..', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "ossystems_capistrano_library/version"

# Capistrano::CLI is only loaded when called by the command line. That means the
# user is calling a capistrano task. So only in that case we load the recipes.
if defined? Capistrano::CLI
  require 'capistrano'
  require 'capistrano/configuration'

  if not Capistrano::Configuration.instance
    config = Capistrano::Configuration.new
    Capistrano::Configuration.instance = config
  end

  Capistrano::Configuration.instance.require 'recipes/base'
end
