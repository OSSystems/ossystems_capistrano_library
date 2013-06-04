# OssystemsCapistranoLibrary

A collection of recipes used by O.S. Systems to deploy Rails projects.

## Installation

Add this line to your application's Gemfile:

    gem 'ossystems_capistrano_library', :github => 'OSSystems/ossystems_capistrano_library'

And then execute:

    $ bundle

## Usage

Replace your Capfile to:

    %w( rubygems ossystems_capistrano_library ).each { |lib| require lib }
