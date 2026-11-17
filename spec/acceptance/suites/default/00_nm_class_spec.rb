require 'spec_helper_acceptance'

test_name 'nm class'

describe 'nm class' do
  require_relative('lib/util')
  include NmTestUtil

  hosts.each do |host|
    context "on #{host}" do
      let(:manifest) { File.read('examples/nm.pp') }

      before(:all) do
        # Taken before anything has been applied, on the node as the image
        # shipped it. Compared with the node afterwards.
        @files_before = nm_snapshot(host)
      end

      it 'applies cleanly' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end

      it 'runs and enables NetworkManager' do
        expect(on(host, 'rpm -q NetworkManager').exit_code).to eq 0
        on(host, 'systemctl is-active NetworkManager')
        on(host, 'systemctl is-enabled NetworkManager')
      end

      it 'does not touch NetworkManager.conf, conf.d, system-connections or ifcfg files' do
        expect(nm_snapshot(host)).to eq @files_before # rubocop:disable RSpec/InstanceVariable
      end

      it 'does not change anything under --noop' do
        before = nm_snapshot(host)
        apply_manifest_on(host, manifest, catch_failures: true, noop: true)
        expect(nm_snapshot(host)).to eq before
      end
    end
  end
end
