require 'spec_helper_acceptance'
require 'shellwords'

test_name 'nm class purge_connections'

describe 'nm class purge_connections' do
  require_relative('lib/util')
  include NmTestUtil

  # Puppet source declaring a profile that already exists on the node, with its
  # exact current content, so that the purge keeps it and changes nothing in it.
  def keep_manifest(host, file)
    name = file.sub(%r{\.nmconnection\z}, '')
    content = on(host, "cat #{Shellwords.escape("#{NmTestUtil::CONN_DIR}/#{file}")}").stdout
    content += "\n" unless content.end_with?("\n")
    "nm::connection { '#{name}':\n  content => @(KEEP)\n#{content}KEEP\n}\n"
  end

  hosts.each do |host|
    context "on #{host}" do
      after(:all) do
        nm_cleanup(host, NmTestUtil::PURGE_PROFILES, NmTestUtil::PURGE_DEVICES)
      end

      # purge_connections removes every file in system-connections that Puppet
      # does not manage, so it must never be able to remove a profile that
      # NetworkManager (and so vagrant/SSH) depends on. That is guaranteed
      # here by declaring every profile file already on the node in the same
      # manifest, verbatim, and by refusing to run if one cannot be declared.
      it 'removes profiles it does not manage, and keeps the ones it does' do
        primary_dev = on(host, "ip -o route get 1.1.1.1 | sed -n 's/.* dev \\([^ ]*\\).*/\\1/p'").stdout.strip
        existing = on(host, "ls -A #{NmTestUtil::CONN_DIR}").stdout.split("\n").reject(&:empty?)
        logger.notify("primary device #{primary_dev}: #{on(host, 'nmcli -t -f NAME,FILENAME connection show --active').stdout.inspect}")
        logger.notify("profile files already in system-connections on #{host}: #{existing.inspect}")
        skip 'a profile file on the node cannot be declared verbatim' unless existing.all? { |f| f.match?(%r{\A[A-Za-z0-9 ._-]+\.nmconnection\z}) }

        manifest = <<~PP
          class { 'nm':
            purge_connections => true,
          }

          nm::connection { 'purge-keep':
            content => {
              'connection' => { 'id' => 'purge-keep', 'type' => 'dummy', 'interface-name' => 'dummyp1' },
              'ipv4'       => { 'address1' => '10.70.1.1/24', 'method' => 'manual' },
              'ipv6'       => { 'method' => 'ignore' },
            },
          }

          #{existing.map { |f| keep_manifest(host, f) }.join("\n")}
        PP

        # The managed profiles exist, and the manifest is idempotent, before
        # the purge is the only thing left to change on the node.
        apply_manifest_on(host, manifest, catch_failures: true)
        apply_manifest_on(host, manifest, catch_changes: true)

        # Fixture: a profile somebody created by hand, which Puppet does not
        # know. NetworkManager loads it and creates its device.
        create_remote_file(host, "#{NmTestUtil::CONN_DIR}/purge-stray.nmconnection", <<~KEYFILE)
          [connection]
          id=purge-stray
          type=dummy
          interface-name=dummyp2

          [ipv4]
          address1=10.70.2.1/24
          method=manual

          [ipv6]
          method=ignore
        KEYFILE
        on(host, "chmod 0600 #{NmTestUtil::CONN_DIR}/purge-stray.nmconnection")
        on(host, 'nmcli connection reload')
        on(host, 'for i in $(seq 1 30); do ip -4 -o addr show dev dummyp2 | grep -q " 10.70.2.1/24 " && exit 0; sleep 1; done; exit 1')

        apply_manifest_on(host, manifest, catch_failures: true)
        apply_manifest_on(host, manifest, catch_changes: true)

        on(host, "test -f #{NmTestUtil::CONN_DIR}/purge-keep.nmconnection")
        on(host, "test ! -e #{NmTestUtil::CONN_DIR}/purge-stray.nmconnection")
        existing.each { |f| on(host, "test -f #{Shellwords.escape("#{NmTestUtil::CONN_DIR}/#{f}")}") }

        # Removing the file is not enough: NetworkManager must also drop the
        # profile it already loaded, and with it the device.
        profiles = on(host, 'nmcli -g NAME connection show').stdout.split("\n")
        expect(profiles).to include('purge-keep')
        expect(profiles).not_to include('purge-stray')
        on(host, 'for i in $(seq 1 30); do ip link show dummyp2 >/dev/null 2>&1 || exit 0; sleep 1; done; ip addr show dummyp2; exit 1')

        # and the node's own connectivity is untouched
        expect(on(host, "nmcli -g GENERAL.STATE device show #{primary_dev}").stdout).to include 'connected'
      end
    end
  end
end
