load 'deploy'

# ================================================================
# ROLES
# ================================================================


role :app, "my_app_server"
role :db,  "my_app_server", {:primary => true}

# ================================================================
# VARIABLES
# ================================================================

set :apache_init_script, "/etc/init.d/apache2"
set :application, "my_app"
set :deploy_to, "/opt/my_app"
set :deploy_via, :export
set :mod_rails_restart_file, "/opt/my_app/current/tmp/restart.txt"
set :rails_env, "production"
set :repository, "https://dev_server/my_repo"
set :runner, "root"
set :scm, "subversion"
set :scm_username, "scm_user"
set :scm_password, "scm_secret"
set :use_sudo, false
set :user, "user"
set :password, "test"

set :enterprise_ruby_baseurl, 'http://rubyforge.org/frs/download.php/41040'
set :enterprise_ruby_tarball, 'ruby-enterprise-1.8.6-20080810.tar.gz'

set :ibm_db2_baseurl, 'http://dev_server/db2_mirror'
set :ibm_db2_tarball, 'db2exc_950_LNX_x86.tar.gz'
set :ibm_db2_extract_location, 'exp'
set :ibm_db2_deb_baseurl, 'ftp://ftp.software.ibm.com/software/data/db2/express/latest_debs/debs_i386/'
set :ibm_db2_deb_package, 'db2exc_9.5.0-1_i386.deb'

set :ibm_db2_initialization, ['create database my_app',
                              'connect to my_app',
                              'create bufferpool my_app8k IMMEDIATE pagesize 8K',
                              'create bufferpool my_app32k IMMEDIATE pagesize 32K',
                              'create regular tablespace my_app pagesize 8K bufferpool my_app8k',
                              'create system temporary tablespace temp_8k pagesize 8K bufferpool my_app8k',
                              'CREATE  LARGE  TABLESPACE USERSPACE3 PAGESIZE 32K BUFFERPOOL my_app32k',
                              'create schema my_app',
                              'disconnect my_app']

set :ibm_db2_db2inst1_password, 'db2inst1'

set :deb_packages, ['apache2',
                    'apache2-mpm-worker',
                    'apache2.2-common',
                    'less',
                    'subversion',
                    'build-essential',
                    'zlib1g-dev',          # for enterprise-ruby
                    'libssl-dev',          # for enterprise-ruby
                    'apache2-prefork-dev', # for passenger
                    'wget',
                    'telnet',
                    'tar',
                    'libstdc++5',          # for DB2
                    'libaio1',             # for DB2
                    'libasound2',          # for DB2
                    'imagemagick',         # for rmagick
                    'libmagick9-dev',      # for rmagick
                    'librmagick-ruby',     # for rmagick
                    'syslog-ng',           # for logging to syslog    
                    'libmysqlclient15-dev',# for mysql gem
                    'mysql-client']        # for mysql gem

set :gems,         ['rmagick -v 1.15.11',
                    'passenger --no-ri --no-rdoc']

set :static_folders, {'public/images/user_images' => 'user_images',
                      'attachments' => 'attachments'}



# ================================================================
# TEMPLATE TASKS
# ================================================================

# allocate a pty by default as some systems have problems without
default_run_options[:pty] = true
      
# set Net::SSH ssh options through normal variables
# at the moment only one SSH key is supported as arrays are not
# parsed correctly by Webistrano::Deployer.type_cast (they end up as strings)
[:ssh_port, :ssh_keys].each do |ssh_opt|
  if exists? ssh_opt
    logger.important("SSH options: setting #{ssh_opt} to: #{fetch(ssh_opt)}")
    ssh_options[ssh_opt.to_s.gsub(/ssh_/, '').to_sym] = fetch(ssh_opt)
  end
end
      
namespace :webistrano do
  namespace :mod_rails do
    desc "start mod_rails & Apache"
    task :start, :roles => :app, :except => { :no_release => true } do
      as = fetch(:runner, "app")
      invoke_command "#{apache_init_script} start", :via => run_method, :as => as
    end
            
    desc "stop mod_rails & Apache"
    task :stop, :roles => :app, :except => { :no_release => true } do
      as = fetch(:runner, "app")
      invoke_command "#{apache_init_script} stop", :via => run_method, :as => as
    end
    
    desc "restart mod_rails"
    task :restart, :roles => :app, :except => { :no_release => true } do
      as = fetch(:runner, "app")
      sudo "#{apache_init_script} stop"
      invoke_command "touch #{mod_rails_restart_file}", :via => run_method, :as => as
      sudo "#{apache_init_script} start"
    end
  end
end
        
namespace :deploy do
  task :restart, :roles => :app, :except => { :no_release => true } do
    webistrano.mod_rails.restart
  end
  
  task :start, :roles => :app, :except => { :no_release => true } do
    webistrano.mod_rails.start
  end
      
  task :stop, :roles => :app, :except => { :no_release => true } do
    webistrano.mod_rails.stop
  end
end
        
# ================================================================
# NODE PREPARATION TASKS
# ================================================================

namespace :node_prep do
  
  desc "Sets some symlinks to misc config files"
  task :symlink_statics, :roles => :app do
    static_folders.each do |t,s|
      run "rm -Rf #{current_path}/#{t} || echo"
      run "ln -s #{shared_path}/#{s} #{current_path}/#{t}"
    end

    run "rm -Rf #{current_path}/config/database.yml"
    run "ln -s #{shared_path}/database.yml #{current_path}/config/database.yml"
        
  end        

  desc "Creates static folders, ferret index folder and database.yml"
  task :create_static_folders, :roles => :app do
    static_folders.each do |t,s|
      run "mkdir -p #{shared_path}/#{s}"
    end
          
    run "mkdir -p #{shared_path}/index"
      
    database_yml = <<-EOF
development:
  adapter: ibm_db
  database: my_app
  schema: my_app
  username: db2inst1
  password: #{ibm_db2_db2inst1_password}
  host: localhost
  port: 50000

test:
  adapter: ibm_db
  database: my_app_test
  schema: my_app
  username: db2inst1
  password: #{ibm_db2_db2inst1_password}
  host: localhost
  port: 50000

production:
  adapter: ibm_db
  database: my_app
  schema: my_app
  username: db2inst1
  password: #{ibm_db2_db2inst1_password}
  host: localhost
  port: 50000
EOF
    put database_yml, "#{shared_path}/database.yml"   
          
  end
        
  desc "Sets up node_prep"
  task :initialize_app, :roles => :app do
    deploy.update
    chown_folders
    setup_globalize
    deploy.migrate
    load_data
  end
  
  desc "Chowns folders"
  task :chown_folders, :roles => :app do
    # chown folders
    sudo "chown #{user}:www-data -Rf #{shared_path}/*"
    sudo "chown #{user}:www-data -Rf #{current_path}/*"
  end
  
  desc "Sets up Globalize tables"
  task :setup_globalize, :roles => :app do
    # setup globalize
    rake = fetch(:rake, "rake")
    env = fetch(:rails_env, "app")
    run "cd #{current_path}; #{rake} RAILS_ENV=#{env} globalize:setup"
  end

  desc "Loads default data for my_app"
  task :load_data, :roles => :app do
    rake = fetch(:rake, "rake")
    env = fetch(:rails_env, "app")
    run "cd #{current_path}; #{rake} RAILS_ENV=#{env} my_app:loaddata"
  end


  desc "Prepares a cluster node for an application server"  
  task :prepare_app_node, :roles => :app do  
    install_base
    install_db2
  end
  
  desc 'Installs Apache2, Enterprise Ruby, mod_rails, and gems'
  task :install_base, :roles => :app do
    
    # install deb packages
    sudo "apt-get update"
    sudo "apt-get install #{deb_packages.join ' '} -y"  
  
    # install enterprise ruby
    sudo "rm -Rf #{enterprise_ruby_tarball.gsub(/.tar.gz/,'')}* || echo" #cleaning up before
    run "wget #{enterprise_ruby_baseurl}/#{enterprise_ruby_tarball}"
    run "tar xzvf #{enterprise_ruby_tarball}"
    sudo "./#{enterprise_ruby_tarball.gsub(/.tar.gz/,'')}/installer -a /usr/lib/ruby"
    sudo "rm -Rf #{enterprise_ruby_tarball.gsub(/.tar.gz/,'')}*" #cleaning up after me
  
    # symlink ruby executables to /usr/bin
    sudo "ln -s /usr/lib/ruby/bin/* /usr/bin || echo" 

    # installing gems
    gems.each do |gem|
      sudo "/usr/lib/ruby/bin/gem install #{gem}"
    end
  
    # symlink again as we possibly compiled some new executables
    sudo "ln -s /usr/lib/ruby/bin/* /usr/bin || echo"  
  
    # install passenger
    sudo "passenger-install-apache2-module" do |channel,stream,line|
      puts line
      channel.send_data "\n" if line =~ /(Press Enter to continue, or Ctrl-C to abort\.)|(Press ENTER to continue\.)/
    end

    # configure apache/phusion
    sudo "a2dissite 000-default || echo" # disable apache default site
    apache_config =<<-EOF
LoadModule passenger_module /usr/lib/ruby/lib/ruby/gems/1.8/gems/passenger-2.0.3/ext/apache2/mod_passenger.so
PassengerRoot /usr/lib/ruby/lib/ruby/gems/1.8/gems/passenger-2.0.3
PassengerRuby /usr/lib/ruby/bin/ruby
PassengerMaxPoolSize 10
PassengerMaxInstancesPerApp 5
PassengerPoolIdleTime 300
RailsBaseURI /

DocumentRoot #{current_path}/public
<Directory #{current_path}/public>
  ExpiresActive On
  ExpiresDefault "access plus 10 years"
  Options FollowSymLinks
  AllowOverride None
  Order allow,deny
  Allow from all
</Directory>

#ExtendedStatus On
#<Location /server-status>
#  SetHandler server-status
#  order deny,allow
#  deny from all
#  allow from 127.0.0.1
#</Location>
EOF
    put apache_config, "apache_config"
    sudo "mv apache_config /etc/apache2/sites-available/#{application}"
    sudo "a2ensite #{application} || echo"
    sudo "a2enmod expires || echo" # enabling expires module (for Expires headers in http)
    sudo "mkdir -p #{deploy_to}"
    sudo "chown #{user}.www-data #{deploy_to} -Rf"
  end  
  
  desc 'Installs IBM DB2 including base database'
  task :install_db2, :roles => :app do

    # UNCOMMENT THESE LINES TO INSTALL DB2 USING GENERAL INSTALLER
    #   sudo "rm -Rf #{ibm_db2_tarball.gsub(/.tar.gz/,'')}* || echo" #cleaning up before
    #   sudo "rm -Rf #{ibm_db2_extract_location} || echo" #cleaning up before
    #   run "wget #{ibm_db2_baseurl}/#{ibm_db2_tarball}"
    #   run "tar xzvf #{ibm_db2_tarball}"
    #   response_file =<<-EOF
    # PROD                          = UDB_EXPRESS_EDITION
    # FILE                          = /opt/ibm/db2/V9.5
    # LIC_AGREEMENT                 = ACCEPT        
    # INTERACTIVE                   = YES            
    # INSTALL_TYPE                  = TYPICAL       
    # INSTANCE                      = db2inst1
    # db2inst1.NAME                 = db2inst1      
    # db2inst1.GROUP_NAME           = db2iadm1      
    # db2inst1.HOME_DIRECTORY       = /home/db2inst1
    # db2inst1.PASSWORD             = db2inst1 
    # db2inst1.AUTOSTART            = YES      
    # db2inst1.START_DURING_INSTALL = YES   
    # db2inst1.FENCED_USERNAME      = db2fenc1  
    # db2inst1.FENCED_GROUP_NAME    = db2fadm1 
    # db2inst1.FENCED_PASSWORD      = db2fenc1
    # EOF
    #   put response_file, 'db2exp.rsp'
    #   sudo "./exp/db2setup -r db2exp.rsp"  

    run "wget #{ibm_db2_deb_baseurl}/#{ibm_db2_deb_package}"
    sudo "dpkg -i #{ibm_db2_deb_package}"

    sudo "/usr/lib/ruby/bin/gem install ibm_db"

    # create database, schema, table spaces, bufferpools
    sudo "su - db2inst1 -c '#{ibm_db2_initialization.map{|c|'/home/db2inst1/sqllib/bin/db2 '+c}.join(';')}'"

    # change password of db2inst1 user
    sudo "passwd db2inst1" do |channel,stream,line|
      puts line
      channel.send_data "#{ibm_db2_db2inst1_password}\n" if line =~ /(Enter new UNIX password)|(Retype new UNIX password)/
    end

  end

  before "deploy:setup", 'node_prep:prepare_app_node'
  after  "deploy:setup", 'node_prep:create_static_folders'

  after "deploy:symlink", 'node_prep:symlink_statics'
  
end

# ================================================================
# RECIPES from http://errtheblog.com/posts/19-streaming-capistrano
# ================================================================

namespace :streaming do
  desc "check production log files in textmate(tm)" 
  task :mate_logs, :roles => :app do

    require 'tempfile'
    tmp = Tempfile.open('w')
    logs = Hash.new { |h,k| h[k] = '' }

    run "tail -n500 #{shared_path}/log/production.log" do |channel, stream, data|
      logs[channel[:host]] << data
      break if stream == :err
    end

    logs.each do |host, log|
      tmp.write("--- #{host} ---\n\n")
      tmp.write(log + "\n")
    end

    exec "mate -w #{tmp.path}" 
    tmp.close
  end

  desc "tail production log files" 
  task :tail_logs, :roles => :app do
    run "tail -f #{shared_path}/log/production.log" do |channel, stream, data|
      puts  # for an extra line break before the host name
      puts "#{channel[:host]}: #{data}" 
      break if stream == :err    
    end
  end

end