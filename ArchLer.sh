#!/bin/bash
if [ $EUID != 0 ]; then
    echo "Please run as root"
    exit
fi
clear
echo       "###     ########    ##########   ##      ##   ##         #########  ########"
echo      "#   #    ##    ##    ##           ##      ##   ##         ##         ##    ##"
echo     "######    #######     ##           ##########   ##         #########  #######"
echo    "#      #   ##    ###   ##           ##      ##   ##         ##         ##   ###"
echo   "#        #  ##    ###   ##########   ##      ##   ########   #########  ##   ###"
echo
echo "v 1.0"
echo
echo

########################################
# FUNCTIONS
########################################
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
        sudo mkdir /root/.gnupg
        sudo touch /root/.gnupg/dirmngr
        sudo touch /root/.gnupg/dirmngr_ldapservers.conf
    else
        echo "Already fixed!"
    fi
}

catalyst_driver() {
        echo "Adding catalyst key to pacman..."
        fix_pacman_key
        sudo pacman-key --init
        sudo pacman-key -r 653C3094
        sudo pacman-key --lsign-key 653C3094
        read -p "Enable multilib... Press a key to continue"
        sudo nano /etc/pacman.conf
        sudo pacman -Syy
        echo -n "Do you have hybrid graphics card? (Intel/AMD) (y/n) (Enter = n): "
        read hyb
        if [ "$hyb" == "y" ]; then
                sudo pacman -S catalyst-hook catalyst-utils-pxp lib32-catalyst-utils-pxp qt4 xf86-video-intel
        else
                sudo pacman -S catalyst-hook catalyst-utils catalyst-libgl opencl-catalyst lib32-catalyst-utils lib32-catalyst-libgl lib32-opencl-catalyst qt4
        fi
        sudo systemctl enable catalyst-hook
        sudo systemctl start catalyst-hook
        read -p "Add nomodeset to your grub boot parameters... Press a key to continue"
        sudo nano /etc/default/grub
        sudo grub-mkconfig -o /boot/grub/grub.cfg
        echo "Blacklisting radeon..."
        echo 'radeon' | sudo tee -a /etc/modprobe.d/modprobe.conf > /dev/null
        echo "Running aticonfig..."
        sudo aticonfig --initial
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
########################################
# SETTINGS
########################################
echo -n "No prompt mode? (y/n) (Enter = y): "
read nop
if [ "$nop" == "" -o "$nop" == "y" ]; then
    i=""
    noc="--noconfirm"
else
    i="-i"
    noc=""
fi

########################################
# ARCHLER
########################################
echo -n "Select an option ( i[nstall] - s[etup] - c[onfig] - h[elp] ): "
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
                ;;
            "e")
                ip link
                echo
                echo -n "Select your interface: "
                read ite
                static_ip "$ite"
                ;;
            "s")
                echo "skipping..."
                ;;
            *)
                echo "Invalid option"
                exit
                ;;
        esac;

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

        echo -n "Select a partitioning tool ( p[arted] - c[fdisk] - f[disk] - g[disk] - s[kip] ) (Enter = c): "
        read ptool

        case "$ptool" in
            "p")
                echo -n "select device or partition: /dev/"
                read dev
                parted /dev/"$dev"
                ;;
            "f")
                echo -n "select device or partition: /dev/"
                read dev
                fdisk /dev/"$dev"
                ;;
            "g")
                echo -n "select device or partition: /dev/"
                read dev
                gdisk /dev/"$dev"
                ;;
            "s")
                echo "skipping..."
                ;;
            "c")
                ;&
            *)
                cfdisk
                ;;
        esac;

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
            echo "skipping..."
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

        echo -n "Set your localtime: "
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
                ;;
            "e")
                echo -n "Select a method ( s[tatic IP] - d[hcpcd] ): "
                read ipm
                echo
                ip link
                echo
                echo -n "Select your interface: "
                read ine
                if [ "$ipm" == "d" ]; then
                    systemctl enable dhcpcd@"$ine".service
                else
                    static_ip "$ine"
                fi
                ;;
            "s")
                echo "skip"
                ;;
            *)
                echo "Invalid option"
                exit
                ;;
        esac;

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
            echo -n "Select a bootloader ( g[rub] ) (Enter = g): "
            read loader
            case "$loader" in
                "g")
                ;&
                *)
                    pacman -S $noc grub
                    echo -n "Scan all oses? (y/n) (Enter = n): "
                    read scan
                    if [ "$scan" == "y" ]; then
                        pacman -S $noc os-prober
                    else
                        echo "skipping..."
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
                    ;;
            esac;
        else
            echo "skipping..."
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
        ;;
    "c")
        ########################################
        # INSTALL A DE
        ########################################
        echo -n "Install a Desktop Environment? (y/n) (Enter = y): "
        read desk
        if [ "$desk" == "y" -o "$desk" == "" ]; then
            echo -n "Select your DE ( o[penbox] - x[fce4] ) (default: o): "
            read de
            case "$de" in
                "x")
                    sudo pacman -S $noc lightdm lightdm-gtk-greeter xfce4
                    sudo systemctl enable lightdm.service
                    ;;
                "o")
                ;&
                *)
                    sudo pacman -S $noc openbox xorg-server xorg-xinit nitrogen pulseaudio ntp
                    ;;
            esac;
        else
            echo "skipping..."
        fi

        ########################################
        # FIX THAT F* DIRMNGR
        ########################################
        echo -n "Do you want to fix pacman-key? (dirmngr and server errors) (y/n) (Enter = y): "
        read fdir
        if [ "$fdir" == "" -o "$fdir" == "y" ]; then
            fix_pacman_key
        else
            echo "skipping..."
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

        echo -n "Select a gfx driver ( i[ntel] - a[ti] - c[atalyst] - ca[talyst-hd234k] - n[ouveau] ): "
        read gfx
        case "$gfx" in
            "i")
                sudo pacman -S $noc xf86-video-intel
                ;;
            "a")
                sudo pacman -S $noc xf86-video-ati
                ;;
            "c")
                echo "Adding catalyst repo to pacman.conf..."
                echo | sudo tee -a /etc/pacman.conf
                echo "[catalyst]" | sudo tee -a /etc/pacman.conf
                echo "Server = http://catalyst.wirephire.com/repo/catalyst/\$arch" | sudo tee -a /etc/pacman.conf
                echo "## Mirrors, if the primary server does not work or is too slow:" | sudo tee -a /etc/pacman.conf
                echo "#Server = http://70.239.162.206/catalyst-mirror/repo/catalyst/\$arch" | sudo tee -a /etc/pacman.conf
                echo "#Server = http://mirror.rts-informatique.fr/archlinux-catalyst/repo/catalyst/\$arch" | sudo tee -a /etc/pacman.conf
                echo "#Server = http://mirror.hactar.bz/Vi0L0/catalyst/\$arch" | sudo tee -a /etc/pacman.conf
                catalyst_driver
                ;;
            "ca")
                echo "Adding catalyst-hd234k repo to pacman.conf..."
                echo | sudo tee -a /etc/pacman.conf
                echo "[catalyst-hd234k]" | sudo tee -a /etc/pacman.conf
                echo "Server = http://catalyst.wirephire.com/repo/catalyst-hd234k/\$arch" | sudo tee -a /etc/pacman.conf
                echo "## Mirrors, if the primary server does not work or is too slow:" | sudo tee -a /etc/pacman.conf
                echo "#Server = http://70.239.162.206/catalyst-mirror/repo/catalyst-hd234k/\$arch" | sudo tee -a /etc/pacman.conf
                echo "#Server = http://mirror.rts-informatique.fr/archlinux-catalyst/repo/catalyst-hd234k/\$arch" | sudo tee -a /etc/pacman.conf
                echo "#Server = http://mirror.hactar.bz/Vi0L0/catalyst-hd234k/\$arch" | sudo tee -a /etc/pacman.conf
                catalyst_driver
                ;;
            "n")
                sudo pacman -S $noc xf86-video-nouveau
                ;;
            *)
                echo "Invalid option, skipping..."
                ;;
        esac;

        ########################################
        # AUR
        ########################################
        echo -n "Do you want to install Yaourt? (y/n) (Enter = n): "
        read yt
        if [ "$yt" == "y" ]; then
             echo | sudo tee -a /etc/pacman.conf
             echo "[archlinuxfr]" | sudo tee -a /etc/pacman.conf
             echo "SigLevel = Never" | sudo tee -a /etc/pacman.conf
             echo "Server = http://repo.archlinux.fr/\$arch" | sudo tee -a /etc/pacman.conf
             sudo pacman -Syy
             sudo pacman -S $noc yaourt
        else
             echo "skipping..."
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
            echo "skipping..."
        fi
        ;;
    "h")
        echo "Welcome to ArchLer!"
        echo "This script will help you to install ArchLinux quickly."
        echo
        echo "Choose (i) to install ArchLinux, choose (s) complete the installation in chroot, choose (c) to customize your ArchLinux box"
        echo "The (c) option gives you the ability to load an external script (custom.sh) to do everything you need to complete the configuration of your newly installed os"
        echo
        echo "Some things are still missing, like UEFI, nvidia nonfree drivers and more."
        echo "A manual installation/configuration is required for thoose packages"
        ;;
    *)
        echo "Invalid option"
        exit
        ;;
esac;
