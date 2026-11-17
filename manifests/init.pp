# @summary
#   Manage NetworkManager
#
#   A bare `include nm` installs and runs NetworkManager and changes nothing
#   else. Every file the class manages, and every purge, must be requested
#   with a parameter.
#
# @param conf
#   Content of `NetworkManager.conf`. When unset (the default) the file is
#   not managed. Setting it takes ownership of the whole file: anything
#   not in this value is removed, and NetworkManager restarts when it
#   changes.
#
#   If a String:
#   Verbatim content of `NetworkManager.conf`.
#
#   If a Hash:
#   Hash of data to serialize to `NetworkManager.conf`.
#
#   See: https://networkmanager.dev/docs/api/latest/nm-settings-keyfile.html
#
# @param connections
#   Hash of nm::connection resources to create
#
# @param purge_connections
#   If `true`, unmanaged connection profiles in
#   `/etc/NetworkManager/system-connections` are removed.
#
# @param purge_ifcfg
#   If `true`, manage `/etc/sysconfig/network-scripts` and remove every file
#   in it that Puppet does not manage (except `readme-ifcfg-rh.txt`), to
#   prevent conflicts between `ifcfg-*` files and `.nmconnection` files.
#   When `false` the directory is not managed.
#
# @param purge_conf_d
#   If `true`, manage `/etc/NetworkManager/conf.d` and remove every
#   drop-in file in it that Puppet does not manage. When `false` the
#   directory is not managed.
#
class nm (
  Optional[Variant[String[1], Hash[String, Hash]]] $conf = undef,
  Optional[Hash[String, Hash]] $connections = undef,
  Boolean $purge_connections = false,
  Boolean $purge_ifcfg = false,
  Boolean $purge_conf_d = false,
) {
  $conf_dir = '/etc/NetworkManager'
  $conf_d_dir = "${conf_dir}/conf.d"
  $conn_dir = "${conf_dir}/system-connections"

  include nm::install
  include nm::service

  if $purge_ifcfg {
    # remove ifcfg-* files to prevent conflicts between ifcfg- and .nmconnection
    file { '/etc/sysconfig/network-scripts':
      ensure  => 'directory',
      purge   => true,
      recurse => true,
      force   => true,
      ignore  => 'readme-ifcfg-rh.txt',
      require => Package['NetworkManager'],
    }
  }

  if $purge_conf_d {
    # remove any conflicting nm drop-in config files
    file { $conf_d_dir:
      ensure  => 'directory',
      purge   => true,
      recurse => true,
      force   => true,
      require => Package['NetworkManager'],
    }
  }

  # write NetworkManager.conf, only when asked to
  if $conf =~ NotUndef {
    $ini_config = { 'quote_char' => undef }

    $_real_conf = $conf ? {
      String  => $conf,
      default => extlib::to_ini($conf, $ini_config),
    }

    file { "${conf_dir}/NetworkManager.conf":
      ensure  => 'file',
      mode    => '0644',
      content => $_real_conf,
      require => Package['NetworkManager'],
      notify  => Service['NetworkManager'],
    }
  }

  # the keyfiles live here; unmanaged profiles are only removed on request
  file { $conn_dir:
    ensure  => 'directory',
    purge   => $purge_connections,
    recurse => $purge_connections,
    force   => true,
    require => Package['NetworkManager'],
    notify  => Exec['nmcli conn reload'],
  }

  if $connections {
    $connections.each | $_name, $_params  | {
      nm::connection { $_name:
        * => $_params,
      }
    }
  }

  exec { 'nmcli conn reload':
    command     => '/bin/nmcli conn reload',
    refreshonly => true,
    timeout     => 30,
    tries       => 3,
    try_sleep   => 10,
  }
}
