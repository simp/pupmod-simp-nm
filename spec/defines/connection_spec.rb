# frozen_string_literal: true

require 'spec_helper'

shared_examples 'ensure param' do
  context 'with ensure =>' do
    context 'with absent' do
      let(:params) { { content: 'bar', ensure: 'absent' } }

      it do
        is_expected.to contain_file('/etc/NetworkManager/system-connections/foo.nmconnection').with(
          ensure: 'absent',
        )
      end
    end

    context 'with present' do
      let(:params) { { content: 'bar', ensure: 'present' } }

      it do
        is_expected.to contain_file('/etc/NetworkManager/system-connections/foo.nmconnection').with(
          ensure: 'file',
        )
      end
    end
  end
end

describe 'nm::connection' do
  on_supported_os.each do |os, facts|
    context "on #{os}" do
      let(:facts) { facts }
      let(:title) { 'foo' }
      let(:pre_condition) do
        <<~PP
          include nm
        PP
      end

      context 'when content is String' do
        let(:params) { { content: 'bar' } }

        it { is_expected.to compile.with_all_deps }

        it do
          is_expected.to contain_file('/etc/NetworkManager/system-connections/foo.nmconnection').with(
            ensure: 'file',
            mode: '0600',
            content: 'bar',
          ).that_notifies('Exec[nmcli conn reload]')
        end

        it_behaves_like 'ensure param'
      end

      context 'when content is Hash' do
        let(:params) do
          {
            content: {
              'bar' => {
                'baz'   => 'quix',
                'quack' => 42,
              }
            }
          }
        end

        it do
          is_expected.to contain_file('/etc/NetworkManager/system-connections/foo.nmconnection').with(
            ensure: 'file',
            mode: '0600',
            content: <<~CONTENT,
              # THIS FILE IS CONTROLLED BY PUPPET

              [bar]
              baz=quix
              quack=42
            CONTENT
          ).that_notifies('Exec[nmcli conn reload]')
        end

        it_behaves_like 'ensure param'
      end

      context 'with defaults' do
        let(:params) { { content: 'bar' } }

        it { is_expected.to have_exec_resource_count(1) }
        it { is_expected.not_to contain_exec('nmcli conn up foo') }
        it { is_expected.not_to contain_file('/etc/sysconfig/network-scripts/ifcfg-eth0') }
      end

      context 'with activate => true' do
        let(:up) { 'nmcli conn up foo' }

        context 'with Hash content that has a connection id' do
          let(:params) do
            { activate: true, content: { 'connection' => { 'id' => 'Wired connection 1', 'type' => 'ethernet' } } }
          end

          it { is_expected.to compile.with_all_deps }

          it do
            is_expected.to contain_exec(up).with(
              command: ['/bin/nmcli', '--wait', '60', 'connection', 'up', 'id', 'Wired connection 1'],
              refreshonly: true,
              timeout: 90,
            ).that_subscribes_to('File[/etc/NetworkManager/system-connections/foo.nmconnection]').that_requires('Exec[nmcli conn reload]')
          end

          it do
            is_expected.to contain_file('/etc/NetworkManager/system-connections/foo.nmconnection').that_notifies('Exec[nmcli conn reload]')
          end
        end

        context 'with Hash content that has no connection id' do
          let(:params) { { activate: true, content: { 'ipv4' => { 'method' => 'auto' } } } }

          it { is_expected.to contain_exec(up).with_command(['/bin/nmcli', '--wait', '60', 'connection', 'up', 'id', 'foo']) }
        end

        context 'with String content' do
          let(:params) { { activate: true, content: "[connection]\nid=bar\n" } }

          it { is_expected.to contain_exec(up).with_command(['/bin/nmcli', '--wait', '60', 'connection', 'up', 'id', 'foo']) }
        end

        context 'with connection_id' do
          let(:params) do
            { activate: true, connection_id: 'my id', content: { 'connection' => { 'id' => 'other' } } }
          end

          it { is_expected.to contain_exec(up).with_command(['/bin/nmcli', '--wait', '60', 'connection', 'up', 'id', 'my id']) }
        end

        context 'with ensure => absent' do
          let(:params) { { activate: true, ensure: 'absent', content: 'bar' } }

          it { is_expected.to compile.with_all_deps }
          it { is_expected.not_to contain_exec(up) }
        end
      end

      context 'with replaces_ifcfg' do
        let(:ifcfg) { '/etc/sysconfig/network-scripts/ifcfg-eth0' }

        context 'when set' do
          let(:params) { { content: 'bar', replaces_ifcfg: 'eth0' } }

          it { is_expected.to compile.with_all_deps }
          it { is_expected.to contain_file(ifcfg).with_ensure('absent').that_notifies('Exec[nmcli conn reload]') }
        end

        context 'when set with ensure => absent' do
          let(:params) { { content: 'bar', ensure: 'absent', replaces_ifcfg: 'eth0' } }

          it { is_expected.not_to contain_file(ifcfg) }
        end

        ['eth0/../x', 'a b', '../eth0', '.hidden', ''].each do |bad|
          context "with invalid value #{bad.inspect}" do
            let(:params) { { content: 'bar', replaces_ifcfg: bad } }

            it { is_expected.to compile.and_raise_error(%r{replaces_ifcfg}) }
          end
        end
      end

      context 'with activate and replaces_ifcfg' do
        let(:params) { { content: 'bar', activate: true, replaces_ifcfg: 'eth0' } }
        let(:keyfile) { 'File[/etc/NetworkManager/system-connections/foo.nmconnection]' }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_file('/etc/sysconfig/network-scripts/ifcfg-eth0').that_notifies('Exec[nmcli conn reload]') }
        it { is_expected.to contain_exec('nmcli conn reload').that_requires(keyfile).that_requires('File[/etc/sysconfig/network-scripts/ifcfg-eth0]') }
        it { is_expected.to contain_exec('nmcli conn up foo').that_requires('Exec[nmcli conn reload]').that_subscribes_to(keyfile) }
      end
    end
  end
end
