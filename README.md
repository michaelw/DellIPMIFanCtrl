Dell IPMI Fan Control
====

Simple ruby script / systemd service for controlling fans with a fan profile on Dell servers.

Requires a linux host OS / hypervisor (such as proxmox or debian) with IPMI / iDRAC6 enabled.
Tested on Dell PowerEdge R210 II and R710 systems, and expected to work with most 11-13th generation PowerEdge machines.

The R210 II BMC applies the fan-speed command but may return completion code `0xcc` (`Invalid data field in request`). On that exact model and command, the controller treats the response as a successful write and logs one warning per process. Other IPMI failures and other server models keep their normal error behavior.

## Install (with systemd)
Install the required packages:
```
apt install lm-sensors ipmitool ruby
```

Clone the repository, and run `ruby install.rb`

The service name is `fanctrl`, and can be managed through the usual suspects of systemctl, journalctl and the like.

Stopping the service restores Dell automatic fan control.

You can change the fan profile by editing `fanctrl.rb`

## Fan speed stabilization

The controller checks the temperature every five seconds. Fan-speed increases are applied immediately. A decrease is applied only when the calculated target remains below the applied duty for a full observation interval, and each decrease is limited to a small step. This avoids large downward changes that can make the temperature rebound while still converging to a stable curve target. Unchanged state is logged every five minutes; applied changes and automatic/manual mode transitions are logged immediately.

The downward controls are configurable:

- `FANCTRL_DECREASE_INTERVAL` is the required sustained-low interval in seconds and defaults to `60`.
- `FANCTRL_DECREASE_STEP` is the maximum percentage-point decrease per interval and defaults to `1`.

Both values must be positive whole numbers, and the step cannot exceed `100`. With the defaults, a stable target of 21% converges from 26% through 25%, 24%, 23%, 22%, and 21% over five minutes. Any required increase remains immediate.

For a systemd installation, use a service override:

```
systemctl edit fanctrl
```

Add the following, then restart the service:

```
[Service]
Environment=FANCTRL_DECREASE_INTERVAL=30
Environment=FANCTRL_DECREASE_STEP=1
```

Invalid values prevent the controller from starting and produce a configuration error in the service journal.

## Run (without systemd)
You will have to run the script manually. You can run `ruby fanctrl.rb` in a cron-job or something similar.

## Credits
`u/tatmde` for the necessary IPMI commands https://www.reddit.com/r/homelab/comments/7xqb11/dell_fan_noise_control_silence_your_poweredge/
