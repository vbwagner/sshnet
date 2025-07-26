# Server configuration lines for sshvpn

# Allow login as root. forced-commands-only will do but we leave less
# restrictive prohibit-password, which is defailt
PermitRootLogin prohibit-password
# Our scripts use point-to-point interfaces
PermitTunnel point-to-point
