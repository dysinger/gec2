class s3backer inherits fuse {
  file { "/usr/local/portage/sys-fs/s3backer":
    source => "puppet:///s3backer/s3backer",
    recurse => true,
    notify => Exec["update-eix-s3backer"],
    before => Portage::Keywords["s3backer"],
    require => Class["fuse"]
  }
  exec { "update-eix-s3backer":
    command => "/usr/bin/update-eix",
    before => Portage::Keywords["s3backer"]
  }
  portage::keywords { "s3backer": category => "sys-fs" }
  package { "s3backer": category => "sys-fs", require => Class["fuse"] }
}
