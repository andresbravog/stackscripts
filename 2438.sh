
#!/bin/bash
# stackscript: RoR with Linux+Nnginx+Mysql+Passenger+RVM+Chef Solo
# Installs System RVM + Ruby 1.9.2 + Nginx + Passenger + MySQL + Git + Bundler + Deploy User
# Alot of this was copied from StackScript 2253.
# For another similar script I looked at script 1635.
# I found this script to be the most complete when creating a new instance.
# Rvm Installation was referenced from 1950


# Things to remember after install or to automate later:
# - adjust server timezone if required
# - put SSL certificate files at /usr/local/share/ca-certificates/
# - set up nginx to point to deployment app and eventual static site
# - (installs logrotate) create logrotate file to the deployed app logs
# - (generates keys)generate github ssh deployment keys
# - setup reverse DNS on Linode control panel
# - run cap production deploy:setup to configure initial files
#
DB_PASSWORD="" # MySQL root Password
R_ENV="production" # Rails/Rack environment to run" default="production"
RUBY_RELEASE="p180" # Ruby 1.9.2 Release" default="p180" example="p180"
DEPLOY_USER="app" # Name of deployment user" default="app"
DEPLOY_PASSWORD="wkresstres" # Password for deployment user"
DEPLOY_SSHKEY="noone" # Deployment user public ssh key"
NEW_HOSTNAME="appserver" # Server's hostname" default="appserver"

exec &> /root/stackscript.log

source 123.sh # Awesome ubuntu utils script
source 1.sh  # Common bash functions

function log {
  echo "### $1 -- `date '+%D %T'`"
}

function system_install_logrotate {
  apt-get -y install logrotate
}

function set_default_environment {
  cat >> /etc/environment << EOF
RAILS_ENV=$R_ENV
RACK_ENV=$R_ENV
EOF
}

function create_deployment_user {
  system_add_user $DEPLOY_USER $DEPLOY_PASSWORD "users,sudo"
  system_user_add_ssh_key $DEPLOY_USER "$DEPLOY_SSHKEY"
  system_update_locale_en_US_UTF_8
  cp ~/.gemrc /home/$DEPLOY_USER/
  chown $DEPLOY_USER:$DEPLOY_USER /home/$DEPLOY_USER/.gemrc
}

function install_essentials {
  aptitude -y install build-essential libpcre3-dev libssl-dev libcurl4-openssl-dev libreadline5-dev libxml2-dev libxslt1-dev libmysqlclient-dev openssh-server git-core
  good_stuff
}

function set_nginx_boot_up {
  wget "http://library.linode.com/web-servers/nginx/installation/reference/init-deb.sh" -O /etc/init.d/nginx
  chmod +x /etc/init.d/nginx
  /usr/sbin/update-rc.d -f nginx defaults
  cat > /etc/logrotate.d/nginx << EOF
/opt/nginx/logs/* {
        daily
        missingok
        rotate 52
        compress
        delaycompress
        notifempty
        create 640 nobody root
        sharedscripts
        postrotate
                [ ! -f /opt/nginx/logs/nginx.pid ] || kill -USR1 `cat /opt/nginx/logs/nginx.pid`
        endscript
}
EOF
}

log "Updating System..."
system_update

log "Installing essentials...includes goodstuff"
install_essentials

log "Setting hostname to $NEW_HOSTNAME"
system_update_hostname $NEW_HOSTNAME

log "Creating deployment user $DEPLOY_USER"
create_deployment_user

log "Setting basic security settings"
system_security_fail2ban
system_security_ufw_install
system_security_ufw_configure_basic
system_sshd_permitrootlogin No
system_sshd_passwordauthentication No
system_sshd_pubkeyauthentication Yes
/etc/init.d/ssh restart

log "installing log_rotate"
system_install_logrotate


log "Installing and tunning MySQL"
mysql_install "$DB_PASSWORD" && mysql_tune 40

log "Installing RVM and Ruby dependencies" >> $logfile
apt-get -y install curl git-core bzip2 build-essential zlib1g-dev libssl-dev

log "Installing RVM system-wide"
bash -s stable < <(curl -s https://raw.github.com/wayneeseguin/rvm/master/binscripts/rvm-installer)
cat >> /etc/profile <<'EOF'
# Load RVM if it is installed,
#  first try to load  user install
#  then try to load root install, if user install is not there.
if [ -s "$HOME/.rvm/scripts/rvm" ] ; then
  . "$HOME/.rvm/scripts/rvm"
elif [ -s "/usr/local/rvm/scripts/rvm" ] ; then
  . "/usr/local/rvm/scripts/rvm"
fi
EOF

source /etc/profile

log "Installing Ruby ree"

rvm install ree
rvm use ree --default

log "Updating Ruby gems"
set_production_gemrc
gem update --system


log "Instaling Phusion Passenger and Nginx"
gem install passenger
passenger-install-nginx-module --auto --auto-download --prefix=/opt/nginx

log "Setting up Nginx to start on boot and rotate logs"
set_nginx_boot_up

log "Setting Rails/Rack defaults"
set_default_environment

log "Install Bundler"
gem install bundler


log "Installing Chef"
gem install chef
log "Configuring Chef solo"
mkdir /etc/chef
cat >> /etc/chef/solo.rb <<EOF
file_cache_path "/tmp/chef"
cookbook_path "/tmp/chef/cookbooks"
role_path "/tmp/chef/roles"
EOF

log "Restarting Services"
restartServices