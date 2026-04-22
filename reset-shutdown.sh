sudo rm -f /etc/cloud/cloud-init.disabled
sudo nano /etc/cloud/cloud.cfg.d/99_hyperv.cfg
sudo cloud-init clean
sudo systemctl enable cloud-init
sudo systemctl enable cloud-init-local
sudo systemctl enable cloud-config
sudo systemctl enable cloud-final
sudo rm /etc/cloud/cloud.cfg.d/99-installer.cfg
sudo rm /etc/cloud/cloud.cfg.d/90-installer-network.cfg
sudo truncate -s 0 /etc/machine-id
sudo rm /var/lib/dbus/machine-id
sudo rm /etc/ssh/ssh_host_*
sudo shutdown now

