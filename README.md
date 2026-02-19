# profile-sync-daemon-installer
Script to install profile-sync-daemon on Arch Linux.
[profile-sync-daemon](https://wiki.archlinux.org/title/Profile-sync-daemon) is a tool that moves your browser profile into RAM for faster loading and less SSD wear.  
Snappier tabs, quicker starts, automatic safe syncs back to disk every hour, crash-recovery backups.  One of my favorite low-effort performance wins on Arch. This script is designed to install and configure this tool. Works with most major browsers, except it will crash if you use Microsoft Edge. You should be ashamed.

# instructions for grandma
Copy and paste.

```
git clone https://github.com/shadowshard4080/profile-sync-daemon-installer.git
cd profile-sync-daemon-installer/
chmod +x psd-installer.sh
bash psd-installer.sh
```
