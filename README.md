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

## Run (without systemd)
You will have to run the script manually. You can run `ruby fanctrl.rb` in a cron-job or something similar.

## Credits
`u/tatmde` for the necessary IPMI commands https://www.reddit.com/r/homelab/comments/7xqb11/dell_fan_noise_control_silence_your_poweredge/
