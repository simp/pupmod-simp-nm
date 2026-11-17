require 'spec_helper_acceptance'

test_name 'nm::connection replaces_ifcfg'

describe 'nm::connection replaces_ifcfg' do
  require_relative('lib/util')
  include NmTestUtil

  def manifest_for(dev)
    <<~PP
      nm::connection { 'keyfile-#{dev}':
        replaces_ifcfg => '#{dev}',
        content        => {
          'connection' => { 'id' => 'keyfile-#{dev}', 'type' => 'dummy', 'interface-name' => '#{dev}' },
          'ipv4'       => { 'address1' => '10.60.1.1/24', 'method' => 'manual' },
          'ipv6'       => { 'method' => 'ignore' },
        },
      }
    PP
  end

  # Number of profiles NetworkManager knows for the device, whichever file
  # they were read from
  def profiles_for(host, dev)
    on(host, "nmcli -g UUID connection show | while read -r u; do nmcli -g connection.interface-name connection show uuid \"$u\"; done | grep -cx #{dev}",
       accept_all_exit_codes: true).stdout.strip.to_i
  end

  def dev
    NmTestUtil::IFCFG_DEV
  end

  def ifcfg
    NmTestUtil::IFCFG_FILE
  end

  hosts.each do |host|
    context "on #{host}" do
      let(:manifest) { manifest_for(dev) }

      # Whether NetworkManager on this node can read ifcfg files at all: the
      # plugin must be installed and enabled. Determined on the node, not by
      # release.
      let(:plugin_file) { on(host, 'find /usr/lib*/NetworkManager -name libnm-settings-plugin-ifcfg-rh.so', accept_all_exit_codes: true).stdout.strip }
      # With no `plugins=` line the plugins compiled into the package apply.
      let(:plugin_enabled) do
        line = on(host, 'NetworkManager --print-config | grep -E "^plugins="', accept_all_exit_codes: true).stdout
        line.empty? || line.include?('ifcfg-rh')
      end
      let(:ifcfg_supported) { !plugin_file.empty? && plugin_enabled }

      after(:all) do
        on(host, "rm -f #{ifcfg} #{NmTestUtil::CONN_DIR}/keyfile-#{dev}.nmconnection", accept_all_exit_codes: true)
        on(host, 'nmcli connection reload', accept_all_exit_codes: true)
        on(host, "ip link delete #{dev}", accept_all_exit_codes: true)
      end

      it 'reports whether the ifcfg-rh plugin is available' do
        logger.notify("ifcfg-rh plugin on #{host}: file=#{plugin_file.inspect} enabled=#{plugin_enabled}")
        logger.notify("#{NmTestUtil::IFCFG_DIR} on #{host}: #{on(host, "ls -A #{NmTestUtil::IFCFG_DIR} 2>&1", accept_all_exit_codes: true).stdout.inspect}")
        on(host, 'rpm -q NetworkManager')
      end

      context 'when NetworkManager reads ifcfg files' do
        it 'sees a profile from an installer-style ifcfg file' do
          skip 'the ifcfg-rh plugin is not installed or enabled on this node' unless ifcfg_supported

          # Fixture: what an installer would have left behind. Not something
          # the module is expected to create. (ifcfg-rh has no dummy type, so the
          # profile is Ethernet, bound to the same interface name.)
          create_remote_file(host, ifcfg, <<~IFCFG)
            DEVICE=#{dev}
            NAME=ifcfg-#{dev}
            TYPE=Ethernet
            BOOTPROTO=none
            IPADDR=10.60.9.1
            PREFIX=24
            ONBOOT=yes
          IFCFG
          on(host, "chmod 0644 #{ifcfg}")
          on(host, 'nmcli connection reload')
          expect(on(host, 'nmcli -g NAME connection show').stdout.split("\n")).to include("ifcfg-#{dev}")
          expect(profiles_for(host, dev)).to eq 1
        end
      end

      context 'when a keyfile for the same device is applied with replaces_ifcfg' do
        it 'applies cleanly' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_changes: true)
        end

        it 'removes the ifcfg file' do
          on(host, "test ! -e #{ifcfg}")
        end

        it 'leaves exactly one profile for the device, the keyfile one' do
          expect(profiles_for(host, dev)).to eq 1
          expect(on(host, 'nmcli -g NAME connection show').stdout.split("\n")).to include("keyfile-#{dev}")
          expect(on(host, 'nmcli -g NAME connection show').stdout.split("\n")).not_to include("ifcfg-#{dev}")
        end

        it 'brings the device up with the keyfile address' do
          on(host, "for i in $(seq 1 30); do ip -4 -o addr show dev #{dev} | grep -q ' 10.60.1.1/24 ' && exit 0; sleep 1; done; ip addr show #{dev}; exit 1")
          expect(nm_addresses(host, dev)).to eq ['10.60.1.1/24']
        end
      end
    end
  end
end
