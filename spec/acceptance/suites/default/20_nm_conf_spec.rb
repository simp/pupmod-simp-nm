require 'spec_helper_acceptance'

test_name 'nm class conf parameter'

describe 'nm class conf parameter' do
  require_relative('lib/util')
  include NmTestUtil

  hosts.each do |host|
    context "on #{host}" do
      before(:all) do
        on(host, "cp -a #{NmTestUtil::CONF_FILE} #{NmTestUtil::CONF_BACKUP}")
      end

      after(:all) do
        # put back what the image shipped, for the suites that follow
        on(host, "cp -a #{NmTestUtil::CONF_BACKUP} #{NmTestUtil::CONF_FILE} && rm -f #{NmTestUtil::CONF_BACKUP}")
        on(host, 'systemctl restart NetworkManager')
      end

      context 'with conf set' do
        let(:manifest) { File.read('examples/nm_conf.pp') }

        it 'applies cleanly and restarts NetworkManager' do
          @pid_before = on(host, 'systemctl show -p MainPID --value NetworkManager').stdout.strip
          apply_manifest_on(host, manifest, catch_failures: true)
          pid = on(host, 'systemctl show -p MainPID --value NetworkManager').stdout.strip
          expect(pid).not_to eq @pid_before # rubocop:disable RSpec/InstanceVariable
          expect(pid).not_to eq '0'
          on(host, 'systemctl is-active NetworkManager')
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_changes: true)
        end

        it 'writes a root-owned 0644 NetworkManager.conf with exactly the given content' do
          expect(on(host, "stat -c '%F %U %G %a' #{NmTestUtil::CONF_FILE}").stdout.strip).to eq 'regular file root root 644'
          expect(on(host, "cat #{NmTestUtil::CONF_FILE}").stdout).to eq <<~CONTENT
            # THIS FILE IS CONTROLLED BY PUPPET

            [main]
            dns=none
            no-auto-default=*
          CONTENT
        end

        it 'does not restart NetworkManager when nothing changed' do
          pid = on(host, 'systemctl show -p MainPID --value NetworkManager').stdout.strip
          apply_manifest_on(host, manifest, catch_changes: true)
          expect(on(host, 'systemctl show -p MainPID --value NetworkManager').stdout.strip).to eq pid
        end
      end

      context 'with conf unset afterwards' do
        it 'leaves the file, and the running service, as they were' do
          sum = on(host, "sha256sum #{NmTestUtil::CONF_FILE}").stdout
          stat = on(host, "stat -c '%U %G %a %Y' #{NmTestUtil::CONF_FILE}").stdout
          pid = on(host, 'systemctl show -p MainPID --value NetworkManager').stdout.strip

          apply_manifest_on(host, 'include nm', catch_failures: true)
          apply_manifest_on(host, 'include nm', catch_changes: true)

          expect(on(host, "sha256sum #{NmTestUtil::CONF_FILE}").stdout).to eq sum
          expect(on(host, "stat -c '%U %G %a %Y' #{NmTestUtil::CONF_FILE}").stdout).to eq stat
          expect(on(host, 'systemctl show -p MainPID --value NetworkManager').stdout.strip).to eq pid
        end
      end
    end
  end
end
