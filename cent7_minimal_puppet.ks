install
url --url http://mirrors.umflint.edu/CentOS/7/os/x86_64
lang en_US.UTF-8
keyboard us
text
skipx
network --bootproto dhcp --device=link
rootpw --iscrypted $1$DTr7SJHS$bZZYT3nACwEEfCw8TKOWI1
timezone --utc America/Detroit

repo --name="Extra Packages for Enterprise Linux" --mirrorlist=https://mirrors.fedoraproject.org/metalink?repo=epel-7&arch=x86_64
repo --name=puppetlabs-products --baseurl=https://yum.puppetlabs.com/el/7/products/x86_64
repo --name=puppetlabs-deps --baseurl=https://yum.puppetlabs.com/el/7/dependencies/x86_64

zerombr
bootloader --location=mbr --append="nofb quiet splash=quiet" 

%include /tmp/diskpart.cfg

reboot

%packages --nobase
@core

puppet
vim-common
vim-enhanced
ntpdate
ntp
wget
tcpdump
git
nc

%end

%pre

#get the actual memory installed on the system and divide by 1024 to get it in MB
act_mem=$((`grep MemTotal: /proc/meminfo | sed 's/^MemTotal: *//'|sed 's/ .*//'` / 1024))

#check if the memory is less than 2GB then swap is double the memory else it is memory plus 2 GB
if [ "$act_mem" -gt 2048 ]; then
    vir_mem=$(($act_mem + 2048))
else
    vir_mem=$(($act_mem * 2))
fi

cat << EOF > /tmp/diskpart.cfg
clearpart --all
part /boot --fstype xfs --size=500
part pv.2 --size=1 --grow
volgroup vg_root --pesize=32768 pv.2
logvol swap --vgname vg_root --name=lv_swap --fstype=swap --size="$vir_mem"
logvol / --vgname vg_root --name lv_root --fstype=xfs --size=10240
logvol /tmp --vgname vg_root --name lv_tmp --fstype=xfs --size=1024 --fsoptions="nodev,nosuid,noexec"
logvol /var/log --vgname vg_root --name lv_var_log --fstype=xfs --size=8192
logvol /var/log/audit --vgname vg_root --name lv_var_log_audit --fstype=xfs --size=1024
logvol /home --vgname vg_root --name lv_home --fstype=xfs --size=1024 --fsoptions="nodev" 
logvol /var --vgname vg_root --name lv_var --fstype=xfs --size=8192 --grow
EOF
%end

%post

# /etc/fstab
echo -e "\n# CIS Benchmark Adjustments" >> /etc/fstab
# CIS 1.1.6
echo "/tmp /var/tmp none bind 0 0" >> /etc/fstab
# CIS 1.1.14-1.1.16
awk '$2~"^/dev/shm$"{$4="nodev,noexec,nosuid"}1' OFS="\t" /etc/fstab >> /tmp/fstab
mv /tmp/fstab /etc/fstab
restorecon -v /etc/fstab && chmod 644 /etc/fstab

%end

%post
logger "Starting anaconda postinstall"
exec < /dev/tty3 > /dev/tty3
#changing to VT 3 so that we can see whats going on....
/usr/bin/chvt 3
(
#update local time
echo "updating system time"
/usr/sbin/ntpdate -sub 0.pool.ntp.org
/usr/sbin/hwclock --systohc

# update all the base packages from the updates repository
yum -t -y -e 0 update


echo "Configuring puppet"
cat > /etc/puppet/puppet.conf << EOF

[main]
logdir = /var/log/puppet
rundir = /var/run/puppet
ssldir = $vardir/ssl
environment = $confdir/environments
basemodulepath = $confdir/modules:/opt/puppet/share/puppet/modules

[agent]
classfile = $vardir/classes.txt
localconfig = $vardir/localconfig

EOF

# Setup puppet to run on system reboot
systemctl enable puppet

%end
