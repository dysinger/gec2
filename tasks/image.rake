# Copyright 2008 Tim Dysinger
# http://www.opensource.org/licenses/mit-license.php

%w(open-uri erb facter).each { |l| require(l) }

namespace(:image) do  
  def chroot(*a)
    script = ['env-update', 'source /etc/profile', a].flatten.join(" && \n")
    File.open('/mnt/gentoo/tmp/rake.sh', 'w')  { |f| f.write script }
    sh('chroot /mnt/gentoo /bin/bash /tmp/rake.sh')
  end

  task(:facts => :env) do
    Facter.search('modules/base/plugins/facter')
    Facter.loadfacts
    Facter.collection.each { |k, v| @env.send("#{k}=", v) }
  end

  directory('/mnt/gentoo')

  file_create('/tmp/stage3-2008.0.tar.bz2' => :facts) do
    sh('wget -O /tmp/stage3-2008.0.tar.bz2 ' <<
       'http://gentoo.osuosl.org/releases/' <<
       "#{@env.architecture =~ /i386/ ? 'x86' : 'amd64'}/current/stages/" <<
       "stage3-#{@env.architecture =~ /i386/ ? 'i686' : 'amd64'}-2008.0.tar.bz2")
  end

  file_create('/mnt/gentoo/etc' => ['/mnt/gentoo',
                                    '/tmp/stage3-2008.0.tar.bz2']) do
    sh('tar -vxjf /tmp/stage3-2008.0.tar.bz2 -C /mnt/gentoo')
    rm('/mnt/gentoo/etc/make.conf')
  end

  file_create('/mnt/gentoo/etc/resolv.conf' => '/mnt/gentoo/etc') do
    cp('/etc/resolv.conf', '/mnt/gentoo/etc')
  end

  file_create('/mnt/gentoo/etc/make.conf' => '/mnt/gentoo/etc') do
    File.open('/mnt/gentoo/etc/make.conf', 'w') do |f|
      f.write(ERB.new(IO.read('modules/portage/templates/make.conf.erb')).
              result(@env.binding))
    end
  end

  directory('/mnt/gentoo/etc/portage')
  file('/mnt/gentoo/etc/portage' => '/mnt/gentoo/etc')

  file_create('/mnt/gentoo/etc/portage/package.keywords' =>
              '/mnt/gentoo/etc/portage') do
    File.open('/mnt/gentoo/etc/portage/package.keywords', 'w') do |f|
      f.write("app-admin/puppet\n")
      f.write("dev-lang/ruby\n")
      f.write("dev-ruby/facter\n")
      f.write("dev-ruby/rubygems\n")
    end
  end

  file_create('/mnt/gentoo/etc/portage/package.unmask' =>
              '/mnt/gentoo/etc/portage') do
    File.open('/mnt/gentoo/etc/portage/package.unmask', 'w') do |f|
      f.write("dev-lang/ruby\n")
    end
  end

  file_create('/mnt/gentoo/etc/portage/package.use' =>
              '/mnt/gentoo/etc/portage') do
    File.open('/mnt/gentoo/etc/portage/package.use', 'w') do |f|
      f.write("mail-mta/postfix sasl\n")
    end
  end

  file_create('/mnt/gentoo/proc/cpuinfo' => '/mnt/gentoo/etc') do
    sh('mount -t proc none /mnt/gentoo/proc')
  end

  file_create('/mnt/gentoo/dev/random' => '/mnt/gentoo/etc') do
    sh('mount -o bind /dev /mnt/gentoo/dev')
  end

  file_create('/mnt/gentoo/etc/mtab' => '/mnt/gentoo/etc') do
    cp('/etc/mtab', '/mnt/gentoo/etc')
  end

  file_create('/mnt/gentoo/tmp/key.pem' => '/mnt/gentoo/etc') do
    File.open('/mnt/gentoo/tmp/key.pem', 'w') do |f|
      f.write("#{@env.key.strip}\n")
    end
  end

  file_create('/mnt/gentoo/tmp/cert.pem' => '/mnt/gentoo/etc') do
    File.open('/mnt/gentoo/tmp/cert.pem', 'w') do |f|
      f.write("#{@env.cert.strip}\n")
    end
  end

  directory('/mnt/gentoo/usr/local/portage')

  desc("bootstrap the image & tune for ec2")
  task(:bootstrap => '.bootstrap.')
  file_create('.bootstrap.' => ['/mnt/gentoo/etc/resolv.conf',
                                '/mnt/gentoo/etc/make.conf',
                                '/mnt/gentoo/etc/portage/package.keywords',
                                '/mnt/gentoo/etc/portage/package.unmask',
                                '/mnt/gentoo/etc/portage/package.use',
                                '/mnt/gentoo/usr/local/portage',
                                '/mnt/gentoo/proc/cpuinfo',
                                '/mnt/gentoo/dev/random']) do
    chroot('groupmems -p -g users',
           "usermod -p `dd if=/dev/urandom count=50 2>/dev/null" <<
           " | md5sum | cut -d ' ' -f1-1` root",
           'emerge --sync',
           'echo CONFIG_PROTECT=\"-*\" >>/etc/make.conf',
           'emerge -e -k system',
           "perl -p -i -e 's/^CONFIG_PROTECT.*//g' /etc/make.conf",
           'update-ca-certificates',
           'python-updater',
           'hash -r',
           'emerge -k gentoolkit',
           'revdep-rebuild',
           'emerge --depclean',
           'emerge -k postfix',
           'emerge -k vixie-cron',
           'emerge -k ruby rubygems',
           'emerge -k puppet')
    touch('.bootstrap.')
  end

  desc("configure the image as a puppet node")
  task(:configure => '.configure.')
  file_create('.configure.' => '.bootstrap.') do
    unless File.exists?('/mnt/gentoo/tmp/ge2c')
      cp_r(Dir.pwd, "/mnt/gentoo/tmp/")
      cp("modules/puppet/files/fileserver.conf",
         "/mnt/gentoo/tmp/gec2/")
    end
    unless File.exists?('/mnt/gentoo/tmp/gec2/run/puppetmasterd.pid')
      chroot('puppetmasterd -vd --confdir /tmp/gec2 --vardir /tmp/gec2 \
              --autosign true')
    end
    chroot('puppetd --confdir /tmp/gec2 --vardir /tmp/gec2 \
            --server `hostname -f` --no-daemonize --test -d \
            --pluginsync true --factpath /tmp/gec2/lib/facter')
    if File.exists?('/mnt/gentoo/tmp/gec2/run/puppetmasterd.pid')
      sh('kill `cat /mnt/gentoo/tmp/gec2/run/puppetmasterd.pid`')
    end
    touch('.configure.')
  end

  desc("bundle the image for ec2")
  task(:bundle => '/mnt/gentoo/tmp/image.manifest.xml')
  file_create('/mnt/gentoo/tmp/image.manifest.xml' => ['/mnt/gentoo/tmp/key.pem',
                                                       '/mnt/gentoo/tmp/cert.pem',
                                                       '/mnt/gentoo/etc/mtab',
                                                       '.configure.']) do
    chroot("ec2-bundle-vol -b -u #{@env.owner_id} " <<
           "-k /tmp/key.pem -c /tmp/cert.pem " <<
           "-a -e /root,/dev,/proc,/sys,/tmp,/var/tmp,/mnt " <<
           "--no-inherit -r #{@env.architecture} " <<
           "--fstab /etc/fstab --kernel #{@env.ec2_kernel_id} -d /tmp")
  end

  task(:default => :upload)
  desc("upload and register an image")
  task(:upload => '.upload.')
  file_create('.upload.' => '/mnt/gentoo/tmp/image.manifest.xml') do
    bname = "gentoo-#{@env.ec2_instance_type}-#{@env.ec2_instance_cpu}"<<
      "-#{Time.now.to_i}"
    AWS::S3::Base.establish_connection!(:access_key_id =>
                                        @env.access_key_id,
                                        :secret_access_key =>
                                        @env.secret_access_key)
    AWS::S3::Bucket.create(bname)
    chroot("ec2-upload-bundle -b #{bname} -a #{@env.access_key_id} " <<
           "-s #{@env.secret_access_key} -m /tmp/image.manifest.xml " <<
           "--url http://s3.amazonaws.com",
           "ec2-register -K /tmp/key.pem -C /tmp/cert.pem " <<
           "#{bname}/image.manifest.xml")
    touch('.upload.')
    puts(":)")
  end
end

