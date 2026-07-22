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

## Fan speed deadband

The controller checks the temperature every five seconds. Fan-speed increases are applied immediately, while decreases are held until the calculated target is at least five percentage points below the currently applied duty. This avoids repeated IPMI writes caused by small temperature fluctuations without delaying additional cooling. Unchanged state is logged every five minutes; applied changes and automatic/manual mode transitions are logged immediately.

Set `FANCTRL_DEADBAND` to change the downward deadband. It accepts a whole number from `0` through `100` and defaults to `5`. A value of `0` applies every integer fan-speed change while still skipping writes when the target is unchanged.

For a systemd installation, use a service override:

```
systemctl edit fanctrl
```

Add the following, then restart the service:

```
[Service]
Environment=FANCTRL_DEADBAND=3
```

Invalid values prevent the controller from starting and produce a configuration error in the service journal.

## Run (without systemd)
You will have to run the script manually. You can run `ruby fanctrl.rb` in a cron-job or something similar.

## Credits
`u/tatmde` for the necessary IPMI commands https://www.reddit.com/r/homelab/comments/7xqb11/dell_fan_noise_control_silence_your_poweredge/
