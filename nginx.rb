dep 'vhost enabled' do
  requires 'vhost configured'
  met? { File.exists? "/opt/nginx/conf/vhosts/on/#{domain}.conf" }
  meet { sudo "ln -sf '/opt/nginx/conf/vhosts/#{domain}.conf' '/opt/nginx/conf/vhosts/on/#{domain}.conf'" }
end

dep 'vhost configured' do
  requires 'webserver configured'
  met? { %w[conf common].all? {|suffix| File.exists? "/opt/nginx/conf/vhosts/#{domain}.#{suffix}" } }
  meet {
    render_erb 'nginx/vhost.conf.erb',   :to => "/opt/nginx/conf/vhosts/#{domain}.conf"
    render_erb 'nginx/vhost.common.erb', :to => "/opt/nginx/conf/vhosts/#{domain}.common"
  }
end

def build_nginx opts = {}
  in_dir "~/src/", :create => true do
    sudo("mkdir -p /opt/nginx/conf/vhosts/on") and
    get_source("http://sysoev.ru/nginx/nginx-#{opts[:nginx_version]}.tar.gz") and
    get_source("http://www.grid.net.ru/nginx/download/nginx_upload_module-#{opts[:upload_module_version]}.tar.gz") and
    failable_shell("sudo passenger-install-nginx-module", :input => [
      '', # enter to continue
      '2', # custom build
      File.expand_path("nginx-#{opts[:nginx_version]}"), # path to nginx source
      '', # accept /opt/nginx target path
      "--with-http_ssl_module --add-module='#{File.expand_path "nginx_upload_module-#{opts[:upload_module_version]}"}'",
      '', # confirm settings
      '', # enter to continue
      '' # done
      ].join("\n")
    )
  end
end

dep 'webserver running' do
  requires 'webserver configured', 'webserver startup script'
  met? {
    returning shell "netstat -an | grep -E '^tcp.*\\.80 +.*LISTEN'" do |result|
      log_result "There is #{result ? 'something' : 'nothing'} listening on #{result ? result.scan(/[0-9.*]+\.80/).first : 'port 80'}.", :result => result
    end
  }
  meet {
    if linux?
      sudo 'update-rc.d nginx defaults'
      sudo '/etc/init.d/nginx start'
    elsif osx?
      sudo 'launchctl load -w /Library/LaunchDaemons/org.nginx.plist'
    end
  }
end

dep 'webserver startup script' do
  requires 'webserver installed', 'rcconf'
  met? {
    if linux?
      shell("rcconf --list").val_for('nginx') == 'on'
    elsif osx?
      shell('sudo launchctl list') {|shell| shell.stdout.grep 'org.nginx' }
    end
  }
  meet {
    if linux?
      render_erb 'nginx/nginx.init.d', :to => '/etc/init.d/nginx', :perms => 0755
    elsif osx?
      render_erb 'nginx/nginx.launchd', :to => '/Library/LaunchDaemons/org.nginx.plist'
    end
  }
end

dep 'webserver configured' do
  requires 'webserver installed'
  met? {
    current_passenger_version = IO.read('/opt/nginx/conf/nginx.conf').val_for('passenger_root')
    returning current_passenger_version.ends_with?(GemHelper.has?('passenger')) do |result|
      log_result "nginx is configured to use #{File.basename current_passenger_version}", :result => result
    end
  }
  meet {
    set :passenger_version, GemHelper.has?('passenger')
    render_erb 'nginx/nginx.conf.erb', :to => '/opt/nginx/conf/nginx.conf'
  }
end

dep 'webserver installed' do
  requires 'www user and group', 'build tools'
  met? { File.executable?('/opt/nginx/sbin/nginx') }
  meet { build_nginx :nginx_version => '0.7.60', :upload_module_version => '2.0.9' }
end
