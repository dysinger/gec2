class aws {
  file { "/usr/local/portage/sys-cluster": ensure => directory }
  file { "/usr/local/portage/sys-cluster/ec2-ami-tools":
    source => "puppet:///aws/ec2-ami-tools",
    recurse => true,
    before => Portage::Keywords["ec2-ami-tools"],
    require => File["/usr/local/portage/sys-cluster"]
  }
  file { "/usr/local/portage/sys-cluster/ec2-api-tools":
    source => "puppet:///aws/ec2-api-tools",
    recurse => true,
    before => Portage::Keywords["ec2-ami-tools"],
    require => File["/usr/local/portage/sys-cluster"]
  }
  exec { "update-eix-aws":
    command => "/usr/bin/update-eix",
    refreshonly => true,
    subscribe => [
      File["/usr/local/portage/sys-cluster/ec2-ami-tools"],
      File["/usr/local/portage/sys-cluster/ec2-api-tools"]
    ],
    before => [
      Portage::Keywords["ec2-api-tools"],
      Portage::Keywords["ec2-ami-tools"]
    ]
  }
  portage::keywords { [ "ec2-api-tools", "ec2-ami-tools" ]:
    category => "sys-cluster", require => Class["ruby"]
  }
  package { [ "ec2-api-tools", "ec2-ami-tools" ]: category => "sys-cluster" }
  exec { "module-loop":
    command => "/bin/echo loop >>/etc/modules.autoload.d/kernel-2.6",
    unless => "/bin/grep loop /etc/modules.autoload.d/kernel-2.6 1>/dev/null"
  }
  exec { "modprobe-loop":
    command => "/sbin/modprobe loop",
    unless => "/sbin/lsmod | grep loop 1>/dev/null",
    require => Class["kernel"]
  }
}
