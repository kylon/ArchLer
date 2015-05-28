#!/bin/bash

if [ $EUID != 0 ]; then
    echo "Please run as root"
    exit
fi

########################################
# FUNCTIONS
########################################
draw_logo() {
clear
echo       "###     ########    ##########   ##      ##   ##         #########  ########"
echo      "#   #    ##    ##    ##           ##      ##   ##         ##         ##    ##"
echo     "######    #######     ##           ##########   ##         #########  #######"
echo    "#      #   ##    ###   ##           ##      ##   ##         ##         ##   ###"
echo   "#        #  ##    ###   ##########   ##      ##   ########   #########  ##   ###"
echo
echo "v 1.2"
echo
echo
}

netctl_profile() {
    echo -n "enable your profile? (y/n) (Enter = y): "
    read prof
    if [ "$prof" == "y" -o "$prof" == "" ]; then
        echo -n "Profile name: "
        read profn
        netctl enable "$profn"
    else
        echo
    fi
}

fix_pacman_key() {
    if [ ! -d "/root/.gnupg" ]; then
        mkdir /root/.gnupg
        touch /root/.gnupg/dirmngr
        touch /root/.gnupg/dirmngr_ldapservers.conf
    else
        echo "Already fixed!"
    fi
}

catalyst_driver() {
        echo "Adding catalyst key to pacman..."
        fix_pacman_key
        pacman-key --init
        pacman-key -r 653C3094
        pacman-key --lsign-key 653C3094
        read -p "Enable multilib... Press a key to continue"
        nano /etc/pacman.conf
        pacman -Syy
        echo -n "Do you have hybrid graphics card? (Intel/AMD) (y/n) (Enter = n): "
        read hyb
        if [ "$hyb" == "y" ]; then
                pacman -S catalyst-hook catalyst-utils-pxp lib32-catalyst-utils-pxp qt4 xf86-video-intel
        else
                pacman -S catalyst-hook catalyst-utils catalyst-libgl opencl-catalyst lib32-catalyst-utils lib32-catalyst-libgl lib32-opencl-catalyst qt4
        fi
        systemctl enable catalyst-hook
        systemctl start catalyst-hook
        if [ -f "/etc/default/grub" ]; then
            read -p "Add nomodeset to your grub boot parameters... Press a key to continue"
            nano /etc/default/grub
            grub-mkconfig -o /boot/grub/grub.cfg
        else
            echo -n nomodeset >> /boot/loader/entries/arch.conf
        fi
        echo "Blacklisting radeon..."
        echo 'radeon' | tee -a /etc/modprobe.d/modprobe.conf > /dev/null
        echo "Running aticonfig..."
        aticonfig --initial
}

static_ip() {
        echo -n "IP address: "
        read ipa
        echo -n "Router: "
        read rot
        echo -n "DNS: "
        read dns
        echo "interface $1" > /etc/dhcpcd.conf
        echo "static ip_address=$ipa" > /etc/dhcpcd.conf
        echo "static routers=$rot" > /etc/dhcpcd.conf
        echo "static domain_name_servers=$dns" > /etc/dhcpcd.conf
        systemctl restart dhcpcd.service
}

invalid() {
	echo "Invalid option!"
}

skip() {
	echo "skipdping..."
}

draw_logo

########################################
# SETTINGS
########################################
echo -n "No prompt mode? (y/n) (Enter = y): "
read nop
if [ "$nop" == "" -o "$nop" == "y" ]; then
    	i=""
    	noc="--noconfirm"
else
	if [ "$nop" != "n" ]; then
		echo "Assuming 'n'"
	fi
    	i="-i"
    	noc=""
fi

########################################
# ARCHLER
########################################
while true
do
echo -n "Select an option ( i[nstall] - s[etup] - c[onfig] - a[bout] - e[xit] ): "
read ipart

case "$ipart" in
    "i")
        ########################################
        # LOADKEYS
        ########################################
        echo -n "loadkeys: "
        read lang
        loadkeys "$lang"

        ########################################
        # NETWORK CONFIGURATION
        ########################################
	while true
	do
        echo -n "select your network configuration ( w[ireless] - e[th - static IP] - s[kip] ): "
        read nt

        case "$nt" in
            "w")
                iw dev
                echo -n "Do you want to use wifi-menu (y/n) (Enter = y): "
                read rewm
                if [ "$rewm" == "y" -o "$rewm" == "" ]; then
                    echo -n "specify an interface (leave blank on most cases): "
                    read intf
                    if [ "$intf" != "" ]; then
                        wifi-menu "$intf"
                    else
                        wifi-menu
                    fi
                else
                    echo -n "Select an interface: "
                    read intfc
                    ip link set "$intfc" up
                    iw dev "$intfc" scan | grep SSID
                    echo -n "Select your SSID: "
                    read ssid
                    echo -n "$ssid password: "
                    read psk
                    wpa_supplicant -B -i "$intfc" -c<(wpa_passphrase "$ssid" "$psk")
                    dhcpcd "$intfc"
                fi
		break
                ;;
            "e")
                ip link
                echo
                echo -n "Select your interface: "
                read ite
                static_ip "$ite"
		break
                ;;
            "s")
                skip
		break
                ;;
            *)
                invalid
                ;;
        esac;
	done

        ########################################
        # CREATE PARTITION/S
        ########################################
        echo -n "List all partitions? (y/n) (Enter = n): "
        read lp
        if [ "$lp" == "y" ]; then
            clear
            fdisk -l | more
        else
            echo
        fi

	while true
	do
        echo -n "Select a partitioning tool ( p[arted] - c[fdisk] - f[disk] - g[disk] - s[kip] ) (Enter = c): "
        read ptool
	
        case "$ptool" in
            "p")
                echo -n "select device or partition: /dev/"
                read dev
                parted /dev/"$dev"
		break
                ;;
            "f")
                echo -n "select device or partition: /dev/"
                read dev
                fdisk /dev/"$dev"
		break
                ;;
            "g")
                echo -n "select device or partition: /dev/"
                read dev
                gdisk /dev/"$dev"
		break
                ;;
            "c")
		;&
	    "")
		cfdisk
		break
                ;;
	    "s")
                skip
		break
                ;;
            *)
                invalid
                ;;
        esac;
	done

        echo -n "Select the ArchLinux partition: /dev/"
        read pt
        echo -n "Select a filesystem (Enter = ext4): "
        read fs
        if [ "$fs" == "" -o "$fs" == "ext4" ]; then
            mkfs.ext4 /dev/"$pt"
        else
            mkfs."$fs" /dev/"$pt"
        fi

        echo -n "Do you have a swap partition? (y/n) (Enter = n): "
        read swp
        if [ "$swp" == "y" ]; then
            echo -n "Select the swap partition: /dev/"
            read swpp
            mkswap /dev/"$swpp"
            swapon /dev/"$swpp"
        else
            skip
        fi

        ########################################
        # INSTALL ARCHLINUX
        ########################################
        echo "Mounting partition..."
        mount /dev/"$pt" /mnt

        echo -n "Do you have a boot partition? (y/n) (Enter = n): "
        read bp
        if [ "$bp" == "y" ]; then
            echo -n "Select the boot partition: /dev/"
            read bpp
            mkdir -p /mnt/boot
            mount /dev/"$bpp" /mnt/boot
        else
            echo "skipping...."
        fi

        echo -n "Do you have a home partition? (y/n) (Enter = n): "
        read hm
        if [ "$hm" == "y" ]; then
            echo -n "Select the home partition: /dev/"
            read hmp
            mkdir -p /mnt/home
            mount /dev/"$hmp" /mnt/home
        else
            echo "skipping...."
        fi

        echo -n "Do you have custom partitions? (y/n) (Enter = n): "
        read cp
        if [ "$cp" == "y" ]; then
            echo -n "How many partitions? (number): "
            read ncp
            for ((i=0; i<ncp; i++))
                do
                    echo -n "Select the partition: /dev/"
                    read cpp
                    echo -n "Select a mount point: /mnt/"
                    read cpmp
                    mkdir -p /mnt/"$cpmp"
                    mount /dev/"$cpp" /mnt/"$cpmp"
                done
        else
            echo "skipping...."
        fi

        pacstrap $i /mnt base base-devel

        echo "Generating fstab..."
        genfstab -U -p /mnt >> /mnt/etc/fstab

        read -p "Entering arch-chroot, to continue the installation run ArchLer again and select setup... Press a key to continue"
        arch-chroot /mnt /bin/bash
	break
        ;;
    "s")
        ########################################
        # SET LOCALE
        ########################################
        read -p "Uncomment your locale... Press a key to continue"
        nano /etc/locale.gen
        locale-gen

        echo -n "Set your LANG="
        read lng
        echo "Generating locale.conf..."
        echo LANG="$lng" > /etc/locale.conf
        export LANG=$lng

        echo -n "KEYMAP (vconsole.conf): "
        read vcon
        echo KEYMAP="$vcon" > /etc/vconsole.conf

        echo -n "Set your localtime (ex. Europe/Rome): "
        read zone
        echo "Setting localtime..."
        ln -s /usr/share/zoneinfo/"$zone" /etc/localtime

        echo "Setting Hardware Clock..."
        hwclock --systohc --utc

        ########################################
        # NETWORK CONFIGURATION
        ########################################
        echo -n "Write your hostname: "
        read host
        echo "$host" > /etc/hostname
        read -p "Add your hostname to the hosts file... Press a key to continue"
        nano /etc/hosts

	while true
	do
        echo -n "select your network configuration ( w[ireless] - e[th] - s[kip] ): "
        read ntw

        case "$ntw" in
            "w")
                pacman -S $noc iw wpa_supplicant netctl
                echo
                echo
                iw dev
                echo
                echo -n "Do you want to use wifi-menu (y/n) (Enter = y): "
                read rewm
                if [ "$rewm" == "y" -o "$rewm" == "" ]; then
                    pacman -S $noc dialog
                    echo -n "specify an interface (leave blank on most cases): "
                    read intf
                    if [ "$intf" != "" ]; then
                        wifi-menu "$intf"
                    else
                        wifi-menu
                    fi
                    netctl_profile
                else
                    cp /etc/netctl/examples/wireless-wpa /etc/netctl/examples/my-network
                    read -p "Opening nano now, edit your wireless config... Press a key to continue"
                    nano /etc/netctl/examples/my-network
                    netctl enable my-network
                fi

                echo -n "Enable netctl-auto? (y/n) (Enter = n): "
                read auto
                if [ "$auto" == "y" ]; then
                    pacman -S $noc wpa_actiond
                    iw dev
                    echo -n "specify an interface: "
                    read intrf
                    systemctl enable netctl-auto@"$intrf".service
                else
                    echo
                fi
		break
                ;;
            "e")
		while true
		do
                echo -n "Select a method ( s[tatic IP] - d[hcpcd] ) (Enter = d): "
                read ipm
                echo
                ip link
                echo
                echo -n "Select your interface: "
                read ine
                if [ "$ipm" == "" -o "$ipm" == "d" ]; then
                    	systemctl enable dhcpcd@"$ine".service
			break
                elif [ "$ipm" == "s" ]; then
                    	static_ip "$ine"
			break
		else
			invalid
                fi
		done
		break
                ;;
            "s")
                skip
		break
                ;;
            *)
                invalid
                ;;
        esac;
	done

        ########################################
        # RAMDISK
        ########################################
        echo "Creating Ram disk..."
        mkinitcpio -p linux

        ########################################
        # ROOT PASSWORD
        ########################################
        echo "Set root password: "
        passwd

        ########################################
        # BOOTLOADER
        ########################################
        echo -n "Install bootloader? (y/n) (Enter = y): "
        read boot
        if [ "$boot" == "y" -o "$boot" == "" ]; then
	    while true
	    do
            if [ -d /sys/firmware/efi ]; then
                echo -n "Select a bootloader ( gr[ub] - gu[mmiboot] ) (Enter = gr): "
            else
                echo -n "Select a bootloader ( gr[ub] ) (Enter = gr): "
            fi
            read loader
            case "$loader" in
                "")
                    ;&
		"gr")
		    pacman -S $noc grub
                    echo -n "Scan all oses? (y/n) (Enter = n): "
                    read scan
                    if [ "$scan" == "y" ]; then
                        pacman -S $noc os-prober
                    else
                        skip
                    fi
                    echo -n "Select the target partition for grub: /dev/"
                    read tpart
                    grub-install --target=i386-pc --force --recheck /dev/"$tpart"
                    echo -n "Edit grub parameters? (y/n) (Enter = n): "
                    read eg
                    if [ "$eg" == "y" ]; then
                        nano /etc/default/grub
                    else
                        echo
                    fi
                    echo "Generating grub config..."
                    grub-mkconfig -o /boot/grub/grub.cfg
		    break
		    ;;
                "gu")
                    pacman -S $noc gummiboot
                    echo -n "Select the target partition for gummiboot: /dev/"
                    read tpart
                    gummiboot --path=/dev/"$tpart" install
                    root="$(df / | awk '/dev/{printf("%s", $1)}')"
                    echo -e title\\tArch Linux\\nlinux\\t/vmlinuz-linux\\ninitrd\\tinitramfs-linux.img\\troot=$root rw > /dev/"$tpart"/loader/entries/arch.conf
                    echo -e default arch\\ntimeout arch > /dev/"$tpart"/loader/loader.conf
		    break
                    ;;
		*)
                    invalid
                    ;;
            esac;
	    done
        else
	    if [ "$boot" != "n" ]; then
		echo "Assuming 'n'"
	    fi
            skip
        fi

        ########################################
        # CREATE A USER?
        ########################################
        echo -n "Do you want to create a user? (y/n) (Enter = y): "
        read user
        if [ "$user" == "y" -o "$user" == "" ]; then
            echo -n "Name: "
            read name
            echo "Creating user: $name, group: wheel..."
            useradd -m -g wheel -s /bin/bash "$name"
            echo "Set $name password: "
            passwd "$name"
            read -p "Enable sudo, add \"yourname ALL=(ALL) ALL\" without quotes... Press a key to continue"
            nano /etc/sudoers
        else
            echo "You are using root :)"
        fi

        read -p "Done! reboot, run ArchLer.sh from your newly installed OS and select config... Press a key to continue"
	break        
	;;
    "c")
        ########################################
        # FIX THAT F* DIRMNGR
        ########################################
        echo -n "Do you want to fix pacman-key? (dirmngr and server errors) (y/n) (Enter = y): "
        read fdir
        if [ "$fdir" == "" -o "$fdir" == "y" ]; then
            fix_pacman_key
        else
            skip
        fi

        ########################################
        # GRAPHIC DRIVER
        ########################################
        echo -n "List all the graphics cards? (y/n) (Enter = n): "
        read lgfx
        if [ "$lgfx" == "y" ]; then
            lspci | grep VGA
        else
            echo
        fi

	while true
	do
        echo -n "Select a gfx driver ( i[ntel] - a[ti] - c[atalyst] - ca[talyst-hd234k] - n[ouveau] ): "
        read gfx
        case "$gfx" in
            "i")
                pacman -S $noc xf86-video-intel
		break
                ;;
            "a")
                pacman -S $noc xf86-video-ati
		break
                ;;
            "c")
                echo "Adding catalyst repo to pacman.conf..."
                echo | tee -a /etc/pacman.conf
                echo "[catalyst]" | tee -a /etc/pacman.conf
                echo "Server = http://catalyst.wirephire.com/repo/catalyst/\$arch" | tee -a /etc/pacman.conf
                echo "## Mirrors, if the primary server does not work or is too slow:" | tee -a /etc/pacman.conf
                echo "#Server = http://70.239.162.206/catalyst-mirror/repo/catalyst/\$arch" | tee -a /etc/pacman.conf
                echo "#Server = http://mirror.rts-informatique.fr/archlinux-catalyst/repo/catalyst/\$arch" | tee -a /etc/pacman.conf
                echo "#Server = http://mirror.hactar.bz/Vi0L0/catalyst/\$arch" | tee -a /etc/pacman.conf
                catalyst_driver
		break
                ;;
            "ca")
                echo "Adding catalyst-hd234k repo to pacman.conf..."
                echo | tee -a /etc/pacman.conf
                echo "[catalyst-hd234k]" | tee -a /etc/pacman.conf
                echo "Server = http://catalyst.wirephire.com/repo/catalyst-hd234k/\$arch" | tee -a /etc/pacman.conf
                echo "## Mirrors, if the primary server does not work or is too slow:" | tee -a /etc/pacman.conf
                echo "#Server = http://70.239.162.206/catalyst-mirror/repo/catalyst-hd234k/\$arch" | tee -a /etc/pacman.conf
                echo "#Server = http://mirror.rts-informatique.fr/archlinux-catalyst/repo/catalyst-hd234k/\$arch" | tee -a /etc/pacman.conf
                echo "#Server = http://mirror.hactar.bz/Vi0L0/catalyst-hd234k/\$arch" | tee -a /etc/pacman.conf
                catalyst_driver
		break
                ;;
            "n")
                pacman -S $noc xf86-video-nouveau
		break
                ;;
            *)
                invalid
                ;;
        esac;
	done

        ########################################
        # AUR
        ########################################
        echo -n "Do you want to install Yaourt? (y/n) (Enter = n): "
        read yt
        if [ "$yt" == "y" ]; then
             echo | tee -a /etc/pacman.conf
             echo "[archlinuxfr]" | tee -a /etc/pacman.conf
             echo "SigLevel = Never" | tee -a /etc/pacman.conf
             echo "Server = http://repo.archlinux.fr/\$arch" | tee -a /etc/pacman.conf
             pacman -Syy
             pacman -S $noc yaourt
        else
             skip
        fi

        ########################################
        # CUSTOM ACTIONS
        ########################################
        echo -n "Do you want to load custom.sh? (y/n) (Enter = n): "
        read cfunc
        if [ "$cfunc" == "y" ]; then
            echo -n "Path to your custom.sh: "
            read cpath
            source "$cpath"/custom.sh
        else
            skip
        fi
	break
        ;;
    "a")
	draw_logo
        echo "Options:"
        echo
        echo "[i]: Install ArchLinux;"
	echo
	echo "[s]: Initial configuration (arch-chroot);"
	echo
	echo "[c]: Customize your ArchLinux box. This option gives you the ability to load an external script (custom.sh);"
        echo
        echo "Some things are still missing, like a full efi support, nvidia nonfree drivers and more."
        echo "A manual installation/configuration is required for thoose packages."
	echo
	echo "Contributors:"
	echo "maxweis (gummiboot support)"
	echo
	echo
        ;;
    "e")
	break
	;;
    *)
        invalid
        ;;
esac;
done
