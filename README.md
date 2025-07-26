ssh net scripts
===============

OpenSSH has option -w which allows to create fully-functional VPN. But
user have to configure this VPN by hand. 

These script illustrate possible way for this configuration and create
star-like VPN, i.e. several computers can connect one central server
from different providers and from behind than NAT and see each other.

Scripts are linux specific, we expect Linux on both client and server. 
If you want to include FreeBSD, Solaris or Windows into such network,
you have to write equivalent scripts for your system.

All configuration is maintained on the client side. It might not be very
secure solution, but this demonstrates approach where all members of the
network trust each other, and only outside people considered
adversaries.

In order to be able to create tun network interfaces, ssh must have root
permissions. So, we have to login via ssh as root. If you don't have
rights to setup root `authorized_keys` on server, consider use some
other approach such as [sshuttle](https://github.com/sshuttle/sshuttle).

Server setup
------------

First of all, we need some configuration on central server.

1. Enable forwarding of packets between clients.
   Install [sysctl.forward.conf](sysctl.forward.conf) into `/etc/sysctl.d` as
   `99-forward.conf`and issue command
   `sysctl -p /etc/sysctl.d/99-forward.conf`.
   This file contain line which is equivalent of 
   `echo 1 >/proc/sys/net/ipv4/ip_forward`.
2. Allow root login and tunnel creation. Install [sshvpn.sshd_onfig.d](sshvpn.sshd_config.d)
   into `/etc/ssh/sshd_config.d` as `sshvpn` and restart your `sshd`
   using systemctl (if you don't use systemd, you probably know how to
   restart daemons in your init system).
3. Install script [sshnetsetup](sshnetsetup) into /usr/local/bin. This script will be
   executed on the server when client connects, and run remain in memory
   until VPN session ends. 

Key generation
--------------

Second, we have to generate ssh keypair on each of client machines.
I'd recommend to use ed25519 keys, but your mileage may vary.

So, run as root on client machine

```
   ssh-keygen -t ed25519
```

and use empty passphrase. We need our key to be available to systemd
service, so we cannot protect it with passphrase.


Key installation
----------------

Now we have to add content of client's `/root/.ssh/id_ed25519.pub` to
`/root/.ssh/authorized_keys` on server. If you have properly setup host
names on your client machine, last words of these file contents would be
`root@client` where `client` is client machine name. It is quite
important that you can distinguish between your client, and find line
from server's authorized_keys to remove if, for instance one of
notebooks serving as client would be stolen.

Now, when you've added key to authorized keys file you have to restrict
its use are to prevent damage which can be accidently done to server.
Remember, these keys are without passphrase, so anybody who can gain
root on client machine (which is effectively anybody who can get
physical access to machine) can use them.

So, at the beginning the authorized_keys line type:

```
command="/usr/local/bin/sshnetsetup",no-pty,no-agent-forwarding,no-x11-forwarding
```

and separate  it with space from ssh keytype (`ssh-ed25519`).
This would tell sshd, that if user uses this key to log in, they
shouldn't get pseudoterminal (thus effectively preventing interactive
use), and agent forwarding and x11 forwarding are not allowed. Moreover,
instead of login shell specified command (script described in previous section)
should be executed and anything send by client ssh as command should be
passed to it as `SSH_ORIGINAL_COMMAND` environment variable.

Client machine setup
--------------------

On client machine we need to make change to global ssh client
configuration `/etc/ssh/ssh_config`. We relay on ssh LocalCommand
feature to configure client side of network  interface and this feature
is disabled by default. So copy  [sshvpn.ssh_config.d](sshvpn.ssh_config.d) то
`/etc/ssh/ssh_config.d` as `sshvpn.conf`. Next ssh process would read
this file and consider it part of system-wide configuration.

Than install [sshvpn.sudoers](sshvpn.sudoers) into /etc/sudoers.d as sshvpn. This would
allow members of `netdev` group (on Debian it is all interactive users)
to invoke `sshvpn` script.

Copy [sshnetclient](sshnetclient) and [sshvpn](sshvpn) scripts to /usr/local/bin.

Now. most important part. Copy [vpn.conf.example](vpn.conf.example) to `/etc/ssh/vpn.conf`
and edit it to suit your environment. This file is read by both `sshvpn`
script (which invokes ssh) and `sshnetclient` (which is invoked by ssh
using LocalCommand).

You should define following variables:

1. `SERVER` - dns name of the server to ssh to. It may be IP address, but
   remember that it is name/address of server outside vpn, in the public
   network. It is how client finds server to connect to.
2. `MY_IP` - this is IP addess client would set on its side of VPN
   interface. Probably all your clients should have these addresses in
   same /24 subnet and it should start with 192.168 or 10 (i.e. private
   range of IP addresses)
3. `SERVER_IP` IP of server side of VPN point-to-point interface.
   Probably all clients should have it same, and it is typically first
   usable address of the VPN subnet
4. `NET` - network which you designate to VPN. All clients would set
   route to this network to vpn tun interface, and it is how IP packets
   from one client would reach another. Server will known how to reach
   each of active client, and each client will send packets for all
   client to server
5. `SOCKS_PORT` - if you set this variable to some port number, ssh
   process, started with `sshvpn` script would use dynamic port
   forwarding in addition to creation of tun interface. Why keep two ssh
   processes to do these two things, if one would do both.


First connect
-------------

Now, when everything is ready, type `sshvpn` as shell prompt. If you are
member of group `netdev`, it should work without password. 

If you haven't login to server as root before and don't have server host
key in `/root/ssh/known_hosts` (or global `/etc/ssh/known_hosts`) ssh
would ask you to confirm host key. Do it. Then nothing would happen and
script appeares to be hang. But it works. You can ping `SERVER_IP`
specified in the your `vpn.conf` and fro server you can ping IP of this
client.

Interrupt VPN with control-C. 

If you wont to use this vpn only occasionally, it may be enough.
But to start vpn automatically on system boot read next chapter.

Installing ssh vpn as system service
------------------------------------

Copy [sshvpn.service](sshvpn.service) to `/etc/systemd/system`
And run

```
systemctl status sshvpn
```

You would see that service is disabled and stopped. Enable it with

```
systemctl enable ssvpn
```

So it would run on next boot, and start it with

```
systemctl start sshvpn
```

If you are interesting what each line of `sshvpn.service` does, consult
manual pages `systemd.service` and `systemd.unit`.

Note that on notebooks with Wi-Fi connection to internet service often
starts before machine is really connected to network and can ssh to
external servers. This is why we need `Restart` line in our service
file.


