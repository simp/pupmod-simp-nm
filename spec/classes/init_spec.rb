# frozen_string_literal: true

require 'spec_helper'

describe 'nm' do
  on_supported_os.each do |os, facts|
    context "on #{os}" do
      let(:facts) do
        facts
      end

      context 'with no parameters' do
        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_file('/etc/sysconfig/network-scripts') }
        it { is_expected.not_to contain_file('/etc/NetworkManager/conf.d') }
        it { is_expected.not_to contain_file('/etc/NetworkManager/NetworkManager.conf') }

        it do
          is_expected.to contain_file('/etc/NetworkManager/system-connections')
            .with(ensure: 'directory', purge: false, recurse: false, force: true)
            .that_requires('Package[NetworkManager]')
        end

        it do
          is_expected.to contain_exec('nmcli conn reload').with(
            command: '/bin/nmcli conn reload',
            refreshonly: true,
            timeout: 30,
            tries: 3,
            try_sleep: 10,
          )
        end

        it 'declares no purging file resource' do
          purging = catalogue.resources.select { |r| r.type == 'File' && [true, :true, 'true'].include?(r[:purge]) }
          expect(purging).to be_empty
        end
      end

      context 'with purge_connections true' do
        let(:params) { { purge_connections: true } }

        it do
          is_expected.to contain_file('/etc/NetworkManager/system-connections')
            .with(ensure: 'directory', purge: true, recurse: true, force: true)
            .that_requires('Package[NetworkManager]')
            .that_notifies('Exec[nmcli conn reload]')
        end
      end

      context 'with purge_ifcfg true' do
        let(:params) { { purge_ifcfg: true } }

        it do
          is_expected.to contain_file('/etc/sysconfig/network-scripts')
            .with(
              ensure: 'directory',
              purge: true,
              recurse: true,
              force: true,
              ignore: 'readme-ifcfg-rh.txt',
            )
            .that_requires('Package[NetworkManager]')
        end
      end

      context 'with purge_conf_d true' do
        let(:params) { { purge_conf_d: true } }

        it do
          is_expected.to contain_file('/etc/NetworkManager/conf.d')
            .with(ensure: 'directory', purge: true, recurse: true, force: true)
            .that_requires('Package[NetworkManager]')
        end
      end

      context 'with conf as a String' do
        let(:params) { { conf: "[main]\nplugins=keyfile\n" } }

        it do
          is_expected.to contain_file('/etc/NetworkManager/NetworkManager.conf')
            .with(ensure: 'file', mode: '0644', content: "[main]\nplugins=keyfile\n")
            .that_requires('Package[NetworkManager]')
            .that_notifies('Service[NetworkManager]')
        end
      end

      context 'with conf as a Hash' do
        let(:params) { { conf: { 'main' => { 'plugins' => 'keyfile' }, 'logging' => {} } } }

        it do
          is_expected.to contain_file('/etc/NetworkManager/NetworkManager.conf')
            .with(ensure: 'file', mode: '0644')
            .with_content(%r{^\[main\]\nplugins=keyfile\n})
            .with_content(%r{^\[logging\]$})
            .that_requires('Package[NetworkManager]')
            .that_notifies('Service[NetworkManager]')
        end
      end

      context 'with connections param' do
        let(:params) do
          {
            connections: {
              foo: {
                content: 'bar',
              },
              baz: {
                content: 'quix',
              },
            },
          }
        end

        it { is_expected.to contain_nm__connection('foo').with_content('bar') }
        it { is_expected.to contain_nm__connection('baz').with_content('quix') }
      end
    end
  end
end
