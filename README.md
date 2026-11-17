# nm

## Table of Contents

1. [Overview](#overview)
1. [Origin](#origin)
1. [Usage](#usage)
1. [Differences from lsst-nm](#differences-from-lsst-nm)
1. [Reference - An under-the-hood peek at what the module is doing and how](#reference)

## Overview

Manages [NetworkManager](https://networkmanager.dev/) and its connection
profiles, which are written as keyfiles (`.nmconnection`) in
`/etc/NetworkManager/system-connections`.

## Origin

`simp-nm` is a fork of [`lsst-nm`](https://github.com/lsst-it/puppet-nm),
taken at 0.3.0 plus the changes that were unreleased at the time. The `nm`
class and the `nm::connection` defined type keep their names and parameters,
so the two modules cannot be installed side by side. Some defaults differ;
see [Differences from lsst-nm](#differences-from-lsst-nm).

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

A bare `include nm` installs and starts NetworkManager and changes nothing
else: it removes no files and does not touch `NetworkManager.conf`. Every
purge and whole-file takeover is opt-in:

| Parameter | Effect when set |
|---|---|
| `nm::purge_connections` | `true` removes unmanaged profiles in `/etc/NetworkManager/system-connections` |
| `nm::purge_ifcfg` | `true` removes unmanaged files in `/etc/sysconfig/network-scripts` (except `readme-ifcfg-rh.txt`) |
| `nm::purge_conf_d` | `true` removes unmanaged drop-ins in `/etc/NetworkManager/conf.d` |
| `nm::conf` | a String or Hash becomes the whole content of `NetworkManager.conf` |

Purge only after the connections the host needs are managed by Puppet, or
the host can lose its network connection.

## Differences from lsst-nm

`lsst-nm` purged and took over files by default. This module does not:

* `nm::purge_connections` defaults to `false` (was `true`).
* `/etc/sysconfig/network-scripts` is no longer purged; new `nm::purge_ifcfg`
  defaults to `false`.
* `/etc/NetworkManager/conf.d` is no longer purged; new `nm::purge_conf_d`
  defaults to `false`.
* `NetworkManager.conf` is not managed unless `nm::conf` is set (it
  defaulted to `{main: {}, logging: {}}`).

To get the `lsst-nm` behavior back:

```yaml
nm::purge_connections: true
nm::purge_ifcfg: true
nm::purge_conf_d: true
nm::conf:
  main: {}
  logging: {}
```

## Reference

See [REFERENCE](REFERENCE.md)
