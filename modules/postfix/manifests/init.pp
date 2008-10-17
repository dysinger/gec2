class postfix {
  portage::use { "postfix": category => "mail-mta", use => "sasl" }
  package { "postfix":
    category => "mail-mta", before => Exec["postfix-aliases"]
  }
  exec { "postfix-aliases":
    command => "/usr/bin/newaliases",
    creates => "/etc/mail/aliases.db",
    before => Service["postfix"]
  }
  service { "postfix": enable => true, ensure => running }
  package { "pflogsumm": category => "net-mail" }
  cron { "pflogsumm-report":
    command => "/usr/bin/pflogsumm.pl -d yesterday /var/log/messages",
    hour => 0,
    minute => 3
  }
  exec { "postfix-reload":
    command => "/usr/sbin/postfix reload", refreshonly => true
  }
  define setup($admin, $vhost = []) {
    include postfix
    file { "/etc/mail/aliases": content => template("postfix/aliases.erb") }
    file { "/etc/postfix/virtual": content => template("postfix/virtual.erb") }
    exec { "postmap-virtual":
      command => "/usr/sbin/postmap /etc/postfix/virtual",
      subscribe => File["/etc/postfix/virtual"],
      refreshonly => true,
      require => Package["postfix"],
      notify => Exec["postfix-reload"]
    }
    file { "/etc/postfix/main.cf":
      content => template("postfix/main.cf.erb"),
      require => Package["postfix"],
      notify => Exec["postfix-reload"]
    }
  }
}
