# VPN Server Master

Scripts for managing VPN panels and server networking tools.

## VPN Panel Auto Installer v2.0

**Run on a supported Linux server as root** (Debian/Ubuntu and systems using `apt`, `dnf`, or `yum`):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Axiume/vpn-server-master/main/scripts/vpn-installerv2.sh)
```

After its first run, the script installs the `vpn` command. Start the interactive menu with:

```bash
vpn
```

Useful commands:

```bash
vpn --help
vpn --status
vpn --update
vpn --install bbr,firewall,3xui
```

## Important safety notes

- Review scripts before running them with root privileges.
- Installation actions may change firewall rules, open ports, install services or Docker containers, and alter system configuration.
- Several options download and execute installer scripts maintained by third parties. Those scripts can change independently of this repository.
- Make a server snapshot or backup first, and verify cloud-provider firewall rules separately.
- Do not expose any web panel publicly without setting strong credentials and appropriate access controls.
