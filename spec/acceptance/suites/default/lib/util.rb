require 'shellwords'

# Helpers shared by the nm acceptance suites.
module NmTestUtil
  CONF_DIR = '/etc/NetworkManager'.freeze
  CONN_DIR = "#{CONF_DIR}/system-connections".freeze
  IFCFG_DIR = '/etc/sysconfig/network-scripts'.freeze
  CONF_FILE = "#{CONF_DIR}/NetworkManager.conf".freeze
  CONF_BACKUP = '/root/NetworkManager.conf.acceptance-backup'.freeze

  # title => device, for the dummy profiles of each suite. Every device is a
  # dummy, never one of the node's real interfaces.
  CONNECTION_PROFILES = {
    'test1' => { dev: 'dummy1', addr: '10.10.10.10/24', header: true },
    'test2' => { dev: 'dummy2', addr: '10.20.20.20/24', header: true },
    # String content is written verbatim, so no header
    'test3' => { dev: 'dummy3', addr: '10.30.30.30/24', header: false },
  }.freeze
  # 'act space' has a connection id with a space in it
  ACTIVATE_PROFILES = { 'act1' => 'dummya1', 'act space' => 'dummya2', 'act3' => 'dummya3' }.freeze
  IFCFG_DEV = 'dummyf1'.freeze
  IFCFG_FILE = "#{IFCFG_DIR}/ifcfg-#{IFCFG_DEV}".freeze
  PURGE_PROFILES = ['purge-keep', 'purge-stray'].freeze
  PURGE_DEVICES = ['dummyp1', 'dummyp2'].freeze

  # Directory listing (type, owner, mode, size, mtime) and file checksums of
  # everything the nm class could touch. Paths that do not exist are reported
  # as such, so "absent before" and "absent after" compare equal too.
  def nm_snapshot(host)
    paths = ["#{CONF_DIR}/NetworkManager.conf", "#{CONF_DIR}/conf.d", CONN_DIR, IFCFG_DIR]
    cmd = paths.map { |p|
      "if [ -e #{p} ]; then find #{p} -exec stat -c '%n|%F|%U:%G|%a|%s|%Y' {} + | sort; " \
      "find #{p} -type f -exec sha256sum {} + | sort; else echo 'absent #{p}'; fi"
    }.join('; ')
    on(host, cmd).stdout
  end

  # Remove a profile and its device through NetworkManager itself, so a test
  # that failed half way cannot leave state behind for the next one.
  # Only ever called with the names of the dummy profiles the suite created.
  def nm_cleanup(host, names, devices)
    names.each { |n| on(host, "rm -f #{Shellwords.escape("#{CONN_DIR}/#{n}.nmconnection")}", accept_all_exit_codes: true) }
    on(host, '/bin/nmcli connection reload', accept_all_exit_codes: true)
    devices.each { |d| on(host, "ip link delete #{d}", accept_all_exit_codes: true) }
  end

  # `ip -4 -o addr show dev <dev>` addresses, as a sorted array
  def nm_addresses(host, dev)
    on(host, "ip -4 -o addr show dev #{dev}", accept_all_exit_codes: true).stdout.scan(%r{inet (\d+\.\d+\.\d+\.\d+/\d+)}).flatten.sort
  end
end
