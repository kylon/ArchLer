#!/bin/bash

if [ $EUID != 0 ]; then
    echo "Please run as root"
    exit
fi

########################################
# FUNCTIONS
########################################
draw_logo() {
    if [ "$efi" == "yes" ]; then
        bootmode="UEFI"
    else
        bootmode="LEGACY/BIOS"
    fi
    clear
    echo       "###     ########    ##########   ##      ##   ##         #########  ########"
    echo      "#   #    ##    ##    ##           ##      ##   ##         ##         ##    ##"
    echo     "######    #######     ##           ##########   ##         #########  #######"
    echo    "#      #   ##    ###   ##           ##      ##   ##         ##         ##   ###"
    echo   "#        #  ##    ###   ##########   ##      ##   ########   #########  ##   ###"
    echo
    echo "v 2.0 -- $bootmode MODE"
    echo
    echo
}

netctl_profile() {
    ask "enable your profile? (y/n) (Enter = y): "
    if [ "$inpt" == "y" -o "$inpt" == "" ]; then
        ask "Profile name: "
        netctl enable "$inpt"
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

    ask "Do you have hybrid graphics card? (Intel/AMD) (y/n) (Enter = n): "
    if [ "$inpt" == "y" ]; then
        drvpk="catalyst-utils-pxp lib32-catalyst-utils-pxp xf86-video-intel"
    else
        drvpk="catalyst-utils catalyst-libgl opencl-catalyst lib32-catalyst-utils lib32-catalyst-libgl lib32-opencl-catalyst"
    fi

    pacman -S $noc catalyst-hook qt4 $drvpk

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
    ask "IP address: "
    ipa="$inpt"
    ask "Router: "
    rot="$inpt"
    ask "DNS: "
    dns="$inpt"
    echo "interface $1" > /etc/dhcpcd.conf
    echo "static ip_address=$ipa" > /etc/dhcpcd.conf
    echo "static routers=$rot" > /etc/dhcpcd.conf
    echo "static domain_name_servers=$dns" > /etc/dhcpcd.conf
    systemctl restart dhcpcd.service
}

err() {
    if [ "$1" == "inv" ]; then
        echo "Invalid option!"
    else
        echo "skipping..."
    fi
}

ask() {
    echo -n "$1"
    read inpt
}

check() {
    if [ "$?" -ne "0" ]; then
        err inv
        continue
    else
        break
    fi
}

########################################
# SETTINGS
########################################
i="-i"
noc=""
efi="no"

if [ -d /sys/firmware/efi ]; then
    efi="yes"
fi

draw_logo

ask "No prompt mode? (y/n) (Enter = y): "
if [ "$inpt" == "" -o "$inpt" == "y" ]; then
    i=""
    noc="--noconfirm"
else
    echo "Assuming 'n'"
fi

########################################
# ARCHLER
########################################
while true
do
    ask "Select an option ( i[nstall] - s[etup] - c[onfig] - a[bout] - e[xit] ): "

    case "$inpt" in
        "i")
            ########################################
            # LOADKEYS
            ########################################
            while true
            do
            	ask "loadkeys: "
            	loadkeys "$inpt"
                check
            done

            ########################################
            # NETWORK CONFIGURATION
            ########################################
            while true
            do
                ask "select your network configuration ( w[ireless] - e[th - static IP] - s[kip] ): "

		case "$inpt" in
                    "w")
                        iw dev
                        ask "Do you want to use wifi-menu (y/n) (Enter = y): "
                        if [ "$inpt" == "y" -o "$inpt" == "" ]; then
                            ask "specify an interface (leave blank on most cases): "
                            wifi-menu "$inpt"
                        else
                            ask "Select an interface: "
                            ip link set "$inpt" up
							intfc="$inpt"
                            iw dev "$inpt" scan | grep SSID
                            ask "Select your SSID: "
                            ssid="$inpt"
                            ask "$ssid password: "
                            psk="$inpt"
                            wpa_supplicant -B -i "$intfc" -c<(wpa_passphrase "$ssid" "$psk")
                            dhcpcd "$intfc"
                        fi
                        break
                        ;;
                    "e")
                        ip link
                        echo
                        ask "Select your interface: "
                        static_ip "$inpt"
                        break
                        ;;
                    "s")
                        err sk
                        break
                        ;;
                    *)
                        err inv
                        ;;
                esac;
            done

            ########################################
            # CREATE PARTITION/S
            ########################################
            ask "Print partitions details? (y/n) (Enter = n): "
            if [ "$inpt" == "y" ]; then
                clear
                fdisk -l | more
            fi

            while true
            do
                if [ "$efi" == "yes" ]; then
                    efipa="- g[pt/UEFI]"
                else
                    efipa=""
                fi

                echo "WARNING: THIS ACTION WILL ERASE YOUR HDD!"
                ask "Create a new partition table ( m[br/BIOS] $efipa - s[kip] ) (Enter = s): "

                case "$inpt" in
                    "m")
                        ask "Select a device: /dev/"
                        parted /dev/"$inpt" mklabel msdos
                        break
                        ;;
                    "g")
                        if [ "$efi" == "no" ]; then
                            err inv
                            continue
                        fi
                        esize="513"
                        ask "Select a device (an ESP partition will be created): /dev/"
                        epart="$inpt"
                        ask "Size of the ESP partition in MiB (Enter = 513): "
                        if [ "$inpt" != "" ]; then
                            esize="$inpt"
                        fi
                        parted /dev/"$epart" mklabel gpt
                        parted /dev/"$epart" mkpart ESP fat32 1MiB "$esize"MiB
                        parted /dev/"$epart" set 1 boot on
                        mkfs.msdos -F 32 /dev/"$epart"1
                        break
                        ;;
                    "")
                        ;&
                    "s")
                        err sk
                        break
                        ;;
                    *)
                        err inv
                        ;;
                esac;
            done

            while true
            do
                ask "Select a partitioning tool ( p[arted] - c[fdisk] - f[disk] - g[disk] - s[kip] ) (Enter = c): "

                case "$inpt" in
                    "p")
                        ask "select device or partition: /dev/"
                        parted /dev/"$inpt"
                        break
                        ;;
                    "f")
                        ask "select device or partition: /dev/"
                        fdisk /dev/"$inpt"
                        break
                        ;;
                    "g")
                        ask "select device or partition: /dev/"
                        gdisk /dev/"$inpt"
                        break
                        ;;
                    "")
                        ;&
                    "c")
                        cfdisk
                        break
                        ;;
                    "s")
                        err sk
                        break
                        ;;
                    *)
                        err inv
                        ;;
                esac;
            done

            ask "Select the ArchLinux partition: /dev/"
            archpt="$inpt"
            ask "Select a filesystem (Enter = ext4): "
            if [ "$inpt" == "" -o "$inpt" == "ext4" ]; then
                mkfs.ext4 /dev/"$archpt"
            else
                mkfs."$inpt" /dev/"$archpt"
            fi

            ask "Do you have a swap partition? (y/n) (Enter = n): "
            if [ "$inpt" == "y" ]; then
                ask "Select the swap partition: /dev/"
                mkswap /dev/"$inpt"
                swapon /dev/"$inpt"
            else
                err sk
            fi

            ########################################
            # INSTALL ARCHLINUX
            ########################################
            echo "Mounting partition..."
            mount /dev/"$archpt" /mnt

            if [ "$efi" == "no" ]; then
                ask "Do you have a boot partition? (y/n) (Enter = n): "
                if [ "$inpt" == "y" ]; then
                    ask "Select the boot partition: /dev/"
                    mkdir -p /mnt/boot
                    mount /dev/"$inpt" /mnt/boot
                else
                    err sk
                fi
            else
                ask "Select your EFI partition: /dev/"
                efip="$inpt"
                ask "Create a mount point for the EFI partition (Enter = /mnt/boot): /mnt/boot/"
                if [ "$inpt" == "" -o "$inpt" == "/mnt/boot" ]; then
                    mkdir -p /mnt/boot
                    mount /dev/"$efip" /mnt/boot
                else
                    mkdir -p /mnt/boot/"$inpt"
                    mount /dev/"$efip" /mnt/boot/"$inpt"
                fi
            fi

            ask "Do you have a home partition? (y/n) (Enter = n): "
            if [ "$inpt" == "y" ]; then
                ask "Select the home partition: /dev/"
                mkdir -p /mnt/home
                mount /dev/"$inpt" /mnt/home
            else
                err sk
            fi

            ask "Do you have custom partitions? (y/n) (Enter = n): "
            if [ "$inpt" == "y" ]; then
                ask "How many partitions? (number): "
                limit="$inpt"
                for ((i=0; i<limit; i++))
                    do
                        ask "Select the partition: /dev/"
                        cpp="$inpt"
                        ask "Select a mount point: /mnt/"
                        cpmp="$inpt"
                        mkdir -p /mnt/"$cpmp"
                        mount /dev/"$cpp" /mnt/"$cpmp"
                    done
            else
                err sk
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

            ask "Set your LANG="
            echo "Generating locale.conf..."
            echo LANG="$inpt" > /etc/locale.conf
            export LANG=$inpt

            ask "KEYMAP (vconsole.conf): "
            echo KEYMAP="$inpt" > /etc/vconsole.conf

            ask "Set your localtime (ex. Europe/Rome): "
            echo "Setting localtime..."
            ln -s /usr/share/zoneinfo/"$inpt" /etc/localtime

            echo "Setting Hardware Clock..."
            hwclock --systohc --utc

            ########################################
            # NETWORK CONFIGURATION
            ########################################
            ask "Write your hostname: "
            echo "$inpt" > /etc/hostname
            read -p "Add your hostname to the hosts file... Press a key to continue"
            nano /etc/hosts

            while true
            do
                ask "select your network configuration ( w[ireless] - e[th] - s[kip] ): "

                case "$inpt" in
                    "w")
                        pacman -S $noc iw wpa_supplicant netctl
                        echo
                        echo
                        iw dev
                        echo
                        ask "Do you want to use wifi-menu (y/n) (Enter = y): "
                        if [ "$inpt" == "y" -o "$inpt" == "" ]; then
                            pacman -S $noc dialog
                            ask "specify an interface (leave blank on most cases): "
                            wifi-menu "$inpt"
                            netctl_profile
                        else
                            cp /etc/netctl/examples/wireless-wpa /etc/netctl/examples/my-network
                            read -p "Opening nano now, edit your wireless config... Press a key to continue"
                            nano /etc/netctl/examples/my-network
                            netctl enable my-network
                        fi

                        ask "Enable netctl-auto? (y/n) (Enter = n): "
                        if [ "$inpt" == "y" ]; then
                            pacman -S $noc wpa_actiond
                            iw dev
                            ask "specify an interface: "
                            systemctl enable netctl-auto@"$inpt".service
                        fi
                        break
                        ;;
                    "e")
                        while true
                        do
                            ask "Select a method ( s[tatic IP] - d[hcpcd] ) (Enter = d): "
                            ipm="$inpt"
                            echo
                            ip link | more
                            echo
                            ask "Select your interface: "
                            ine="$inpt"
                            if [ "$ipm" == "" -o "$ipm" == "d" ]; then
                                systemctl enable dhcpcd@"$ine".service
                                break
                            elif [ "$ipm" == "s" ]; then
                                static_ip "$ine"
                                break
                            else
                                err inv
                            fi
                        done
                        break
                        ;;
                    "s")
                        err sk
                        break
                        ;;
                    *)
                        err inv
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
            ask "Install bootloader? (y/n) (Enter = y): "
            if [ "$inpt" == "y" -o "$inpt" == "" ]; then
                while true
                do
                    if [ "$efi" == "yes" ]; then
                        efiboot="- gu[mmiboot] "
                    else
                        efiboot=""
                    fi
                    ask "Select a bootloader ( gr[ub] $efiboot- s[kip] ) (Enter = gr): "
                    case "$inpt" in
                        "")
                            ;&
                        "gr")
                            if [ "$efi" == "yes" ]; then
                                ask "Select the EFI directory (Enter = /boot): /boot/"
                                if [ "$inpt" == "" -o "$inpt" == "/boot" ]; then
                                    efid="/boot"
                                else
                                    efid="/boot/$inpt"
                                fi
                                packs="efibootmgr"
                                targ="x86_64-efi"
                                opts="--efi-directory=$efid --bootloader-id=grub"
                            else
                                ask "Select the target partition for grub: /dev/"
                                packs=""
                                targ="i386-pc"
                                opts="/dev/$inpt"
                            fi
                            pacman -S $noc grub $packs
                            ask "Scan all oses? (y/n) (Enter = n): "
                            if [ "$inpt" == "y" ]; then
                                pacman -S $noc os-prober
                            fi
                            grub-install --target="$targ" --force --recheck $opts
                            ask "Edit grub parameters? (y/n) (Enter = n): "
                            if [ "$inpt" == "y" ]; then
                                nano /etc/default/grub
                            fi
                            echo "Generating grub config..."
                            grub-mkconfig -o /boot/grub/grub.cfg
                            ask "Edit grub.cfg? (y/n) (Enter = n): "
                            if [ "$inpt" == "y" ]; then
                                nano /boot/grub/grub.cfg
                            fi
                            break
                            ;;
                        "gu")
                            if [ "$efi" == "no" ]; then
                                err inv
                                continue
                            fi
                            pacman -S $noc gummiboot
                            ask "Select the EFI directory (Enter = /boot): /boot/"
                            if [ "$inpt" == "" -o "$inpt" == "/boot" ]; then
                                efid="/boot"
                            else
                                efid="/boot/$inpt"
                            fi
                            gummiboot --path="$efid" install
                            root="$(df / | awk '/dev/{printf("%s", $1)}')"
                            echo -e title\\tArch Linux\\nlinux\\t/vmlinuz-linux\\ninitrd\\tinitramfs-linux.img\\troot=$root rw > "$efid"/loader/entries/arch.conf
                            echo -e default arch\\ntimeout arch > "$efid"/loader/loader.conf
                            break
                            ;;
                        "s")
                            err sk
                            break
                            ;;
                        *)
                            err inv
                            ;;
                    esac;
                done
            else
                err sk
            fi

            ########################################
            # CREATE A USER?
            ########################################
            ask "Do you want to create a user? (y/n) (Enter = y): "
            if [ "$inpt" == "y" -o "$inpt" == "" ]; then
                ask "Name: "
                echo "Creating user: $inpt, group: wheel..."
                useradd -m -g wheel -s /bin/bash "$inpt"
                echo "Set $inpt password: "
                passwd "$inpt"
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
            ask "Do you want to fix pacman-key? (dirmngr and server errors) (y/n) (Enter = y): "
            if [ "$inpt" == "" -o "$inpt" == "y" ]; then
                fix_pacman_key
            else
                err sk
            fi

            ########################################
            # GRAPHIC DRIVER
            ########################################
            ask "List all the graphics cards? (y/n) (Enter = n): "
            if [ "$inpt" == "y" ]; then
                lspci | grep VGA
            fi

            while true
            do
                ask "Select a gfx driver ( i[ntel] - a[ti] - c[atalyst] - ca[talyst-hd234k] - n[ouveau] - s[kip] ): "
                case "$inpt" in
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
                    "s")
                        err sk
                        break
                        ;;
                    *)
                        err inv
                        ;;
                esac;
            done

            ########################################
            # AUR
            ########################################
            ask "Do you want to install Yaourt? (y/n) (Enter = n): "
            if [ "$inpt" == "y" ]; then
                echo | tee -a /etc/pacman.conf
                echo "[archlinuxfr]" | tee -a /etc/pacman.conf
                echo "SigLevel = Never" | tee -a /etc/pacman.conf
                echo "Server = http://repo.archlinux.fr/\$arch" | tee -a /etc/pacman.conf
                pacman -Syy
                pacman -S $noc yaourt
            else
                err sk
            fi

            ########################################
            # CUSTOM ACTIONS
            ########################################
            ask "Do you want to load custom.sh? (y/n) (Enter = n): "
            if [ "$inpt" == "y" ]; then
                ask "Path to your custom.sh: "
                source "$inpt"/custom.sh
            else
                err sk
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
            err inv
            ;;
    esac;
done
