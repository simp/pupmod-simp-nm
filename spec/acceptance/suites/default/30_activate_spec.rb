require 'spec_helper_acceptance'

test_name 'nm::connection activate'

describe 'nm::connection activate' do
  require_relative('lib/util')
  include NmTestUtil

  def manifest_for(addr_index, activate:)
    flag = activate ? 'true' : 'false'
    <<~PP
      nm::connection { 'act1':
        activate => #{flag},
        content  => {
          'connection' => { 'id' => 'act1', 'type' => 'dummy', 'interface-name' => 'dummya1' },
          'ipv4'       => { 'address1' => '10.51.1.#{addr_index}/24', 'method' => 'manual' },
          'ipv6'       => { 'method' => 'ignore' },
        },
      }

      nm::connection { 'act space':
        activate => #{flag},
        content  => {
          'connection' => { 'id' => 'act space', 'type' => 'dummy', 'interface-name' => 'dummya2' },
          'ipv4'       => { 'address1' => '10.51.2.#{addr_index}/24', 'method' => 'manual' },
          'ipv6'       => { 'method' => 'ignore' },
        },
      }

      # String content, so the id cannot be taken from the content: it comes
      # from connection_id, and differs from the resource title.
      nm::connection { 'act3':
        activate      => #{flag},
        connection_id => 'Third Act',
        content       => @(NM),
          [connection]
          id=Third Act
          type=dummy
          interface-name=dummya3

          [ipv4]
          address1=10.51.3.#{addr_index}/24
          method=manual

          [ipv6]
          method=ignore
          | NM
      }
    PP
  end

  def wait_for_address(host, dev, addr)
    on(host, "for i in $(seq 1 30); do ip -4 -o addr show dev #{dev} | grep -q ' #{addr} ' && exit 0; sleep 1; done; ip addr show #{dev}; exit 1")
  end

  hosts.each do |host|
    context "on #{host}" do
      after(:all) do
        nm_cleanup(host, NmTestUtil::ACTIVATE_PROFILES.keys, NmTestUtil::ACTIVATE_PROFILES.values)
      end

      it 'starts with the three profiles active' do
        apply_manifest_on(host, manifest_for(1, activate: false), catch_failures: true)
        apply_manifest_on(host, manifest_for(1, activate: false), catch_changes: true)
        NmTestUtil::ACTIVATE_PROFILES.each_value.with_index(1) { |dev, i| wait_for_address(host, dev, "10.51.#{i}.1/24") }
        expect(on(host, 'nmcli -g NAME connection show --active').stdout.split("\n")).to include('act1', 'act space', 'Third Act')
      end

      context 'when the keyfiles change without activate' do
        it 'applies cleanly and is idempotent' do
          apply_manifest_on(host, manifest_for(2, activate: false), catch_failures: true)
          apply_manifest_on(host, manifest_for(2, activate: false), catch_changes: true)
        end

        it 'writes the new address to the keyfile and NetworkManager stores it in the profile' do
          expect(on(host, "grep address1 #{NmTestUtil::CONN_DIR}/act1.nmconnection").stdout).to include '10.51.1.2/24'
          expect(on(host, 'nmcli -g ipv4.addresses connection show id act1').stdout.strip).to eq '10.51.1.2/24'
        end

        it 'leaves the live interface on the old address' do
          # Current behavior, documented: the reload makes NetworkManager
          # re-read the profile, but an already-active connection keeps running
          # with the settings it was activated with until it is re-activated.
          NmTestUtil::ACTIVATE_PROFILES.each_value.with_index(1) do |dev, i|
            expect(nm_addresses(host, dev)).to eq ["10.51.#{i}.1/24"]
          end
        end
      end

      context 'when the keyfiles change with activate' do
        it 'applies cleanly and puts the new address on the interface in that one run' do
          apply_manifest_on(host, manifest_for(3, activate: true), catch_failures: true)
          NmTestUtil::ACTIVATE_PROFILES.each_value.with_index(1) do |dev, i|
            expect(nm_addresses(host, dev)).to eq ["10.51.#{i}.3/24"]
          end
        end

        it 'is idempotent, and does not re-activate when nothing changed' do
          apply_manifest_on(host, manifest_for(3, activate: true), catch_changes: true)
        end
      end
    end
  end
end
