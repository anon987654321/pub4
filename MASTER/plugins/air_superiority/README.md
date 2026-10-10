# Air Superiority

**Air Superiority lets a machine know its own airwaves: every Wi-Fi network and
Bluetooth device around it, measured against what its owner has already
vouched for, with nothing sent anywhere and nothing attacked.**

It is a plugin for defensive observation. A scan lists the networks and devices
the host can hear and flags each one that is not on a local list of known
ones. Each flag is advisory. The plugin does not decide that a stranger is a
threat; it tells the operator that a stranger is there.

The scan uses whatever the host already provides. On macOS it reads the airport
tool and the system profiler, on Linux nmcli and bluetoothctl, on OpenBSD
ifconfig, and on Android under Termux the Termux:API scanners. The status
action names the backend chosen for each radio, or says it is unavailable. When
one radio cannot be scanned, the other is still reported, the scan result
carries the error, and its complete flag is false. A missing interface never
becomes an empty success.

The known list is a small YAML file under `~/.master/plugins/air_superiority/`,
kept private to the operator. The remember action adds a network by name and
hardware address, or a device by address, and writes nothing else. The law in
`data/laws.yml` grants write access to that list alone and forbids packet
injection, deauthentication, disassociation, credential capture,
man-in-the-middle tricks, exploitation and remote control. Do not add any of
them. Identifiers the scan finds are sensitive, so they stay on the machine.

The manifest, `plugin.yml`, declares status and scan as observable, which means
MASTER's guarded observation tool may call them without write authority.
Remember is not observable and runs only through an explicit plugin run. Any
other action is refused as unknown. Every call first passes the law handshake,
so the plugin will not run before MASTER has admitted its own constitution.
The code is in `air_superiority.rb`, with the comparison in `analyzer.rb` and
the small result objects in `models.rb`.

## Use

Inside a MASTER session, the plugin command reaches it. Remember takes the same
form with a JSON object naming the kind, network or device, and its identifiers.

```text
/plugin info air_superiority
/plugin run air_superiority status
/plugin run air_superiority scan
```
