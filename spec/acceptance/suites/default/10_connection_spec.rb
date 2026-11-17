require 'spec_helper_acceptance'

test_name 'nm::connection present and absent'

describe 'nm::connection' do
  require_relative('lib/util')
  include NmTestUtil

  hosts.each do |host|
    context "on #{host}" do
      after(:all) do
        nm_cleanup(host, NmTestUtil::CONNECTION_PROFILES.keys, NmTestUtil::CONNECTION_PROFILES.values.map { |p| p[:dev] })
      end

      context 'with the profiles present' do
        let(:manifest) { File.read('examples/connection.pp') }

        it 'applies cleanly' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_changes: true)
        end

        NmTestUtil::CONNECTION_PROFILES.each do |name, p|
          it "writes #{name}.nmconnection as a root-owned 0600 keyfile" do
            file = "#{NmTestUtil::CONN_DIR}/#{name}.nmconnection"
            expect(on(host, "stat -c '%F %U %G %a' #{file}").stdout.strip).to eq 'regular file root root 600'

            header = p[:header] ? "# THIS FILE IS CONTROLLED BY PUPPET\n\n" : ''
            expect(on(host, "cat #{file}").stdout).to eq <<~CONTENT
              #{header}[connection]
              id=#{name}
              type=dummy
              interface-name=#{p[:dev]}

              [ipv4]
              address1=#{p[:addr]}
              method=manual

              [ipv6]
              method=ignore
            CONTENT
          end

          it "brings up #{p[:dev]} with #{p[:addr]}" do
            # NetworkManager creates the device and activates the profile
            # asynchronously after the reload
            on(host, "for i in $(seq 1 30); do ip -4 -o addr show dev #{p[:dev]} | grep -q ' #{p[:addr]} ' && exit 0; sleep 1; done; ip addr show; exit 1")
            expect(nm_addresses(host, p[:dev])).to eq [p[:addr]]
          end
        end
      end

      context 'with the profiles absent' do
        let(:manifest) { File.read('examples/connection_absent.pp') }

        it 'applies cleanly' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_changes: true)
        end

        NmTestUtil::CONNECTION_PROFILES.each do |name, p|
          it "removes #{name}.nmconnection and #{p[:dev]}" do
            on(host, "test ! -e #{NmTestUtil::CONN_DIR}/#{name}.nmconnection")
            on(host, "for i in $(seq 1 30); do ip link show #{p[:dev]} >/dev/null 2>&1 || exit 0; sleep 1; done; ip link show #{p[:dev]}; exit 1")
          end

          it "leaves NetworkManager without a #{name} profile" do
            expect(on(host, 'nmcli -g NAME connection show').stdout.split("\n")).not_to include(name)
          end
        end
      end
    end
  end
end
