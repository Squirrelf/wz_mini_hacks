#!/bin/sh

exec 1> /opt/wz_mini/log/run_mmc.log 2>&1

echo "welcome to run_mmc.sh"
echo "PID $$"

set -x

HOSTNAME="WCV3"

#####NETWORKING#####
ENABLE_USB_ETH="false"

ENABLE_USB_DIRECT="false"
USB_DIRECT_MAC_ADDR="02:01:02:03:04:08"

ENABLE_USB_RNDIS="false"

ENABLE_IPV6="false"

ENABLE_WIREGUARD="false"

ENABLE_IPTABLES="false"

ENABLE_NFSv4="false"

#####ACCESSORIES#####
REMOTE_SPOTLIGHT="false"
REMOTE_SPOTLIGHT_HOST="0.0.0.0"

#####VIDEO STREAM#####
RTSP_ENABLED="false"
RTSP_ENABLE_AUDIO="false"
RTSP_LOGIN="admin"
RTSP_PASSWORD=""
RTSP_PORT="8554"
RTSP_MAX_BITRATE=""
RTSP_TARGET_BITRATE=""
RTSP_ENC_PARAMETER=""

#####GENERAL#####
ENABLE_SWAP="true"
ENABLE_USB_STORAGE="false"
ENABLE_EXT4="false"
ENABLE_CIFS="false"
DISABLE_FW_UPGRADE="false"

#####DEBUG#####
DEBUG_ENABLED="false"
#drops you to a shell via serial, doesn't load app_init.sh

#####################################
##########CONFIG END#################
#####################################

hostname_set() {
	echo "set hostname"
	hostname $HOSTNAME
}

first_run_check() {
	if [[ -e /opt/wz_mini/tmp/.run_mmc_firstrun ]]; then
	echo "run_mmc.sh already run once, exit."
	exit 0
	fi
}

wait_sdroot() {
##Stall execution if the micro-sd card isn't mounted yet, iCamera controls this internally.
    while true
    do
	if [[ -d /media/mmc/wz_mini ]]; then
	echo "sd card ready"
	break
	fi
        echo "sdcard not ready yet..."
        sleep 5
    done

}

store_mac() {
	echo "store original mac"
	cat /sys/class/net/wlan0/address | tr '[:lower:]' '[:upper:]' > /opt/wz_mini/tmp/wlan0_mac
}

wait_wlan() {
##Check if the driver has been loaded for the onboard wlan0, store the MAC.
    while true
    do
        if  ifconfig wlan0 | grep "inet addr";
        then
	store_mac
        break
	elif [[ "$ENABLE_USB_ETH" == "true" || "$ENABLE_USB_DIRECT" == "true" ]]; then
	store_mac
	break
        fi
        echo " wlan0 not ready yet..."
        sleep 5
    done
}

rename_interface() {
##Fool iCamera by renaming the hardline interface to wlan0
	echo "renaming interfaces"
	ifconfig $1 down
	ifconfig wlan0 down
        /media/mmc/wz_mini/bin/busybox ip link set wlan0 name wlanold
        /media/mmc/wz_mini/bin/busybox ip addr flush dev wlanold
        /media/mmc/wz_mini/bin/busybox ip link set $1 name wlan0
	eth_wlan_up
}

eth_wlan_up() {
##Run DHCP client, and bind mount our fake wpa_cli.sh to fool iCamera
	if [[ "$ENABLE_USB_DIRECT" == "true" ]]; then
		/media/mmc/wz_mini/bin/busybox ip link set wlan0 address $USB_DIRECT_MAC_ADDR
	fi
        ifconfig wlan0 up
	pkill udhcpc
        udhcpc -i wlan0 -x hostname:$HOSTNAME -p /var/run/udhcpc.pid -b
        mount -o bind /media/mmc/wz_mini/bin/wpa_cli.sh /bin/wpa_cli
	break
}

wpa_check() {
#Check if wpa_supplicant has been created by iCamera
	if [[ -e /tmp/wpa_supplicant.conf ]]; then
		echo "wpa_supplicant.conf ready"
		wlanold_check $1
	else
		echo "wpa_supplicant.conf not ready, wait some time for creation."
		COUNT=0
		ATTEMPTS=15
		until [[ -e /tmp/wpa_supplicant.conf ]] || [[ $COUNT -eq $ATTEMPTS ]]; do
		echo -e "$(( COUNT++ ))... \c"
		sleep 5
		done
		[[ $COUNT -eq $ATTEMPTS ]] && echo "time exceeded waiting for iCamera, continue potentially broken condition without network." && wlanold_check $1
	fi
}

wlanold_check() {
#Have we renamed interfaces yet?
	if [[ -d /sys/class/net/wlanold ]]; then
		echo "wlanold exist"
		eth_wlan_up
	else
		echo "wlanold doesn't exist"
		rename_interface $1
	fi
}

netloop() {
##While loop for check
        while true
        do
        wpa_check $1
        echo "wlan0 not ready yet..."
        sleep 5
        done
}

swap_enable() {
        if [[ -e /media/mmc/wz_mini/swap ]]; then
                echo "Swap exists, enable"
                swapon /media/mmc/wz_mini/swap
        else
                echo "Swap file missing!"
        fi
}

first_run_check
wait_sdroot
wait_wlan
hostname_set


if [[ "$ENABLE_SWAP" == "true" ]]; then
        if cat /proc/swaps | grep "mini" ; then
        echo "Swap is already enabled"
        else
        echo "Swap not enabled, enabling"
	swap_enable
        fi
fi

if [[ "$ENABLE_IPV6" == "true" ]]; then
	echo "ipv6 enabled"
else
	echo "ipv6 disabled"
	sysctl -w net.ipv6.conf.all.disable_ipv6=1
fi

if [[ "$ENABLE_NFSv4" == "true" ]]; then
        insmod /lib/modules/3.10.14__isvp_swan_1.0__/kernel/lib/oid_registry.ko
        insmod /lib/modules/3.10.14__isvp_swan_1.0__/kernel/net/dns_resolver/dns_resolver.ko
        insmod /lib/modules/3.10.14__isvp_swan_1.0__/kernel/fs/nfs/nfsv4.ko
        insmod /lib/modules/3.10.14__isvp_swan_1.0__/kernel/net/sunrpc/auth_gss/auth_rpcgss.ko
        echo nfsv4 enabled
else
        echo nfsv4 disabled
fi

if [[ "$ENABLE_IPTABLES" == "true" ]]; then

	insmod /lib/modules/3.10.14__isvp_swan_1.0__/kernel/net/netfilter/x_tables.ko
	insmod /lib/modules/3.10.14__isvp_swan_1.0__/kernel/net/ipv4/netfilter/ip_tables.ko
	insmod /lib/modules/3.10.14__isvp_swan_1.0__/kernel/net/ipv4/netfilter/ipt_REJECT.ko
	insmod /lib/modules/3.10.14__isvp_swan_1.0__/kernel/net/ipv4/netfilter/iptable_filter.ko
	insmod /lib/modules/3.10.14__isvp_swan_1.0__/kernel/net/ipv4/netfilter/iptable_mangle.ko
	echo "iptables ipv4 enabled"

	if [[ "$ENABLE_IPV6" == "true" ]]; then
		insmod /lib/modules/3.10.14__isvp_swan_1.0__/kernel/net/ipv6/netfilter/ip6_tables.ko
		insmod /lib/modules/3.10.14__isvp_swan_1.0__/kernel/net/ipv6/netfilter/ip6t_REJECT.ko
		insmod /lib/modules/3.10.14__isvp_swan_1.0__/kernel/net/ipv6/netfilter/ip6table_filter.ko
		insmod /lib/modules/3.10.14__isvp_swan_1.0__/kernel/net/ipv6/netfilter/ip6table_mangle.ko
		echo "iptables ipv6 enabled"
	fi
	else
		echo "iptables disabled"
fi

if [[ "$ENABLE_USB_ETH" == "true" ]]; then

	insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/drivers/net/usb/usbnet.ko
        insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/drivers/net/usb/asix.ko

	if [[ "$ENABLE_SWAP" == "true" ]]; then
	echo "swap already enabled"
	else
	swap_enable
	fi

	netloop eth0

	else
	echo "usb ethernet disabled"
fi

if [[ "$ENABLE_USB_DIRECT" == "true" ]]; then

	#Set dwc2 ID_PIN driver memory
	devmem 0x13500000 32 0x001100cc
	devmem 0x10000040 32 0x0b000096
	#wipe the bits to set the ID_PIN
	devmem 0x10000040 32 0x0b000FFF

	insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/drivers/usb/gadget/libcomposite.ko
	insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/drivers/usb/gadget/u_ether.ko
	insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/drivers/usb/gadget/usb_f_ncm.ko
	insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/drivers/usb/gadget/g_ncm.ko iManufacturer=wz_mini_ncm

	sleep 1

	if [[ "$ENABLE_SWAP" == "true" ]]; then
	echo "swap already enabled"
	else
	swap_enable
	fi

	#loop begin
	while true
	do
	wpa_check usb0
	echo "wlan0 not ready yet..."
        sleep 1
	done
	else
	echo "usb direct disabled"
fi

if [[ "$ENABLE_USB_RNDIS" == "true" ]]; then

	insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/drivers/net/usb/usbnet.ko
	insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/drivers/net/usb/cdc_ether.ko
	insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/drivers/net/usb/rndis_host.ko

	sleep 1

	if [[ "$ENABLE_SWAP" == "true" ]]; then
	echo "swap already enabled"
	else
	swap_enable
	fi

	#loop begin
	while true
	do
	wpa_check usb0
	echo "wlan0 not ready yet..."
        sleep 1
	done
	else
	echo "usb direct disabled"
fi

if [[ "$ENABLE_WIREGUARD" == "true" ]]; then
	insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/net/ipv4/tunnel4.ko
	insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/net/ipv4/ip_tunnel.ko
	insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/net/wireguard/wireguard.ko
else
	echo "wireguard disabled"
fi

if [[ "$ENABLE_CIFS" == "true" ]]; then
	insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/fs/cifs/cifs.ko
else
	echo "cifs disabled"
fi

if [[ "$ENABLE_USB_STORAGE" == "true" ]]; then
	insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/drivers/scsi/scsi_mod.ko
	insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/drivers/scsi/sd_mod.ko
	insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/drivers/usb/storage/usb-storage.ko
else
	echo "usb_storage disabled"
fi

if [[ "$ENABLE_EXT4" == "true" ]]; then
	insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/fs/jbd2/jbd2.ko
	insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/fs/mbcache.ko
	insmod /opt/wz_mini/lib/modules/3.10.14__isvp_swan_1.0__/kernel/fs/ext4/ext4.ko
else
	echo "ext4 disabled"
fi

if [[ "$DISABLE_FW_UPGRADE" == "true" ]]; then
	mkdir /tmp/Upgrade
	mount -t tmpfs -o size=1,nr_inodes=1 none /tmp/Upgrade
	echo -e "127.0.0.1 localhost \n127.0.0.1 wyze-upgrade-service.wyzecam.com" > /opt/wz_mini/tmp/.storage/hosts
	mount --bind /opt/wz_mini/tmp/.storage/hosts /etc/hosts
else
        mkdir /tmp/Upgrade
        /opt/wz_mini/bin/busybox inotifyd /opt/wz_mini/usr/bin/watch_up.sh /tmp/Upgrade:n &
fi

if [[ "$REMOTE_SPOTLIGHT" == "true" ]]; then
	/media/mmc/wz_mini/bin/socat pty,link=/dev/ttyUSB0,raw tcp:$REMOTE_SPOTLIGHT_HOST:9000 &
	echo "remote accessory enabled"
else
	echo "remote accessory disabled"
fi

if [[ "$RTSP_ENABLED" == "true" ]]; then

	if [[ "$ENABLE_SWAP" == "true" ]]; then
	echo "swap already enabled"
	else
	swap_enable
	fi

	/opt/wz_mini/bin/cmd video on
	/opt/wz_mini/bin/cmd audio on


	if [[ "$RTSP_PASSWORD" = "" ]]; then
	RTSP_PASSWORD=$(cat /opt/wz_mini/tmp/wlan0_mac)
	fi

        if [[ "$RTSP_ENABLE_AUDIO" == "true" ]]; then
                LD_LIBRARY_PATH=/media/mmc/wz_mini/lib /media/mmc/wz_mini/bin/v4l2rtspserver -C 1 -a S16_LE  /dev/video1,hw:Loopback,0 -U $RTSP_LOGIN:$RTSP_PASSWORD -P $RTSP_PORT &
        else
                echo "rtsp audio disabled"
                LD_LIBRARY_PATH=/media/mmc/wz_mini/lib /media/mmc/wz_mini/bin/v4l2rtspserver -s /dev/video1 -U $RTSP_LOGIN:$RTSP_PASSWORD -P $RTSP_PORT &
        fi


	if [[ "$RTSP_ENC_PARAMETER" != "" ]]; then
	watch -n5 -t "/system/bin/impdbg --enc_rc_s 0:44:4:$RTSP_ENC_PARAMETER" > /dev/null 2>&1 &
	fi

	if [[ "$RTSP_MAX_BITRATE" != "" ]]; then
	watch -n5 -t "/system/bin/impdbg --enc_rc_s 0:48:4:$RTSP_MAX_BITRATE" > /dev/null 2>&1 &
	fi

	if [[ "$RTSP_TARGET_BITRATE" != "" ]]; then
	watch -n5 -t "/system/bin/impdbg --enc_rc_s 0:52:4:$RTSP_TARGET_BITRATE" > /dev/null 2>&1 &
	fi

        else
        echo "rtsp disabled"

fi

touch /opt/wz_mini/tmp/.run_mmc_firstrun
sync;echo 3 > /proc/sys/vm/drop_caches
sleep 3

#################################################
##############CUSTOM BEGIN#######################
#################################################

#Place commands here to run 30 seconds after boot
#such as mount nfs, ping, etc

#mount -t nfs -o nolock,rw,noatime,nodiratime 192.168.1.1:/volume1 /media/mmc/record &
