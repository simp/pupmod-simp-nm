# @summary
#  Create a .nmconnection file
#
# @param content
#   If a String:
#   Verbatim content of .nmconnection "keyfile".
#
#   If a Hash:
#   Hash of data to serialize to a .nmconnection "keyfile".
#
#   See: https://networkmanager.dev/docs/api/latest/nm-settings-keyfile.html
#
# @param ensure
#   If connection file should be present or absent.
#
# @param activate
#   When `true` and `ensure` is `present`, (re)activate the connection with
#   `nmcli connection up` after NetworkManager has reloaded its profiles, so a
#   changed keyfile takes effect on a connection that is already active. By
#   default the change only takes effect the next time the connection is
#   activated.
#
#   Re-activating the connection that the Puppet agent itself uses interrupts
#   it briefly, and activating the wrong profile can cut the host off from the
#   network. Use it with care on remote hosts.
#
# @param connection_id
#   The connection `id` that `activate` passes to `nmcli connection up`. When
#   unset, `$content['connection']['id']` is used if `content` is a Hash that
#   has it, otherwise the title of the resource.
#
# @param replaces_ifcfg
#   The name of a device whose `/etc/sysconfig/network-scripts/ifcfg-<device>`
#   file is removed when `ensure` is `present`, so the profile it describes
#   does not exist alongside this keyfile. Removing a file that does not
#   exist, or from a directory that does not exist, is not an error.
#
define nm::connection (
  Optional[Variant[String[1], Hash[String, Hash]]] $content = undef,
  Enum['present', 'absent'] $ensure = 'present',
  Boolean $activate = false,
  Optional[String[1]] $connection_id = undef,
  Optional[Pattern[/\A[A-Za-z0-9][A-Za-z0-9_.:@-]*\z/]] $replaces_ifcfg = undef,
) {
  include nm

  $_real_ensure = $ensure ? {
    'absent' => 'absent',
    default  => 'file',
  }

  $ini_config = { 'quote_char' => undef }

  $_real_content = $content ? {
    String  => $content,
    Hash    => extlib::to_ini($content, $ini_config),
    default => undef,
  }

  $_keyfile = "${nm::conn_dir}/${name}.nmconnection"

  file { $_keyfile:
    ensure  => $_real_ensure,
    mode    => '0600',
    content => $_real_content,
    notify  => Exec['nmcli conn reload'],
  }

  if $ensure == 'present' {
    if $replaces_ifcfg =~ NotUndef {
      file { "/etc/sysconfig/network-scripts/ifcfg-${replaces_ifcfg}":
        ensure => absent,
        notify => Exec['nmcli conn reload'],
      }
    }

    if $activate {
      $_id = $connection_id ? {
        undef   => $content ? {
          Hash    => pick($content.dig('connection', 'id'), $name),
          default => $name,
        },
        default => $connection_id,
      }

      # `id` makes nmcli treat the argument as a profile name, never as a UUID
      # or D-Bus path. Each argument is passed separately so that a name with
      # spaces is not split.
      exec { "nmcli conn up ${name}":
        command     => ['/bin/nmcli', '--wait', '60', 'connection', 'up', 'id', $_id],
        refreshonly => true,
        timeout     => 90,
        subscribe   => File[$_keyfile],
        require     => Exec['nmcli conn reload'],
      }
    }
  }
}
