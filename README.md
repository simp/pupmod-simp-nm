# nm

## Table of Contents

1. [Overview](#overview)
1. [Origin](#origin)
1. [Usage](#usage)
1. [Reference - An under-the-hood peek at what the module is doing and how](#reference)

## Overview

Manages [NetworkManager](https://networkmanager.dev/) and its connection
profiles, which are written as keyfiles (`.nmconnection`) in
`/etc/NetworkManager/system-connections`.

## Origin

`simp-nm` is a fork of [`lsst-nm`](https://github.com/lsst-it/puppet-nm),
taken at 0.3.0 plus the changes that were unreleased at the time. The `nm`
class and the `nm::connection` defined type keep their names and parameters,
so the two modules are interchangeable but cannot be installed side by side.

## Usage

```puppet
nm::connection { 'eth0':
  content => {
    'connection' => {
      'id'             => 'eth0',
      'type'           => 'ethernet',
      'interface-name' => 'eth0',
    },
    'ipv4'       => {
      'address1' => '192.0.2.10/24,192.0.2.1',
      'method'   => 'manual',
    },
  },
}
```

`nm::connection` can also apply a change to a live device and retire the
`ifcfg` profile that an installer wrote for the same device:

```puppet
nm::connection { 'eth0':
  content        => {
    'connection' => {
      'id'             => 'eth0',
      'type'           => 'ethernet',
      'interface-name' => 'eth0',
    },
  },
  activate       => true,
  replaces_ifcfg => 'eth0',
}
```

With `activate => true`, `nmcli connection up id <id>` runs after
NetworkManager reloads its profiles. `<id>` is `connection_id`, else
`content['connection']['id']`, else the resource title. Re-activating the
connection the Puppet agent uses interrupts it briefly, and activating the
wrong profile can cut the host off. `replaces_ifcfg` removes
`/etc/sysconfig/network-scripts/ifcfg-<device>` in the same run. Both are off
by default.

By default the `nm` class removes every connection profile, `ifcfg` file and
`NetworkManager/conf.d` drop-in that Puppet does not manage. Set
`nm::purge_connections` to `false` to keep unmanaged connection profiles.

## Reference

See [REFERENCE](REFERENCE.md)
