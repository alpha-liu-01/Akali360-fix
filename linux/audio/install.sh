#!/bin/sh
set -eu
cd "$(dirname "$0")"
UCM=/usr/share/alsa/ucm2
install -d "$UCM/Akali360" \
	"$UCM/conf.d/avs_da7219" \
	"$UCM/conf.d/avs_max98357a" \
	/etc/wireplumber/wireplumber.conf.d
install -m 644 ucm/avs_da7219.conf ucm/avs_da7219-HiFi.conf \
	ucm/avs_max98357a.conf ucm/avs_max98357a-HiFi.conf \
	"$UCM/Akali360/"
ln -sfn ../../Akali360/avs_da7219.conf "$UCM/conf.d/avs_da7219/avs_da7219.conf"
ln -sfn ../../Akali360/avs_max98357a.conf "$UCM/conf.d/avs_max98357a/avs_max98357a.conf"
install -m 644 wireplumber/akali-audio.conf \
	/etc/wireplumber/wireplumber.conf.d/akali-audio.conf

# Drop the per-user overlay. While ALSA_CONFIG_UCM2 points at it, PipeWire
# never reads the files just installed under /usr/share/alsa/ucm2.
clean_user() {
	user=$1
	home=$(getent passwd "$user" | cut -d: -f6)
	uid=$(id -u "$user")
	if [ -z "$home" ] || [ "$home" = / ]; then
		return 0
	fi
	rm -rf "$home/.local/share/alsa/ucm2"
	rm -f "$home/.config/environment.d/akali-ucm.conf"
	rm -f "$home/.config/wireplumber/wireplumber.conf.d/akali-audio.conf"
	nodes="$home/.local/state/wireplumber/default-nodes"
	if [ -f "$nodes" ]; then
		sed -i '/^default\.configured\.audio\.sink/d' "$nodes"
		chown "$user:" "$nodes"
	fi
	if [ -d "/run/user/$uid" ]; then
		sudo -u "$user" XDG_RUNTIME_DIR="/run/user/$uid" \
			systemctl --user unset-environment ALSA_CONFIG_UCM2 || true
		sudo -u "$user" XDG_RUNTIME_DIR="/run/user/$uid" \
			systemctl --user restart wireplumber pipewire pipewire-pulse
		i=0
		while [ "$i" -lt 10 ]; do
			if sudo -u "$user" XDG_RUNTIME_DIR="/run/user/$uid" \
				wpctl status | grep -q 'Built-in Audio'; then
				break
			fi
			i=$((i + 1))
			sleep 1
		done
		echo "==== $user ===="
		sudo -u "$user" XDG_RUNTIME_DIR="/run/user/$uid" wpctl status
		pid=$(sudo -u "$user" XDG_RUNTIME_DIR="/run/user/$uid" \
			systemctl --user show -p MainPID --value pipewire.service)
		if [ -n "$pid" ] && [ "$pid" != 0 ] && [ -r "/proc/$pid/environ" ]; then
			echo "==== pipewire ALSA_CONFIG_UCM2 ===="
			tr '\0' '\n' < "/proc/$pid/environ" | grep '^ALSA_CONFIG_UCM2=' || true
		fi
	fi
}

seen=""
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
	seen="$SUDO_USER"
	clean_user "$SUDO_USER"
fi
for marker in /home/*/.config/environment.d/akali-ucm.conf \
	/home/*/.local/share/alsa/ucm2; do
	[ -e "$marker" ] || continue
	user=$(stat -c %U "$marker")
	case " $seen " in
	*" $user "*) continue ;;
	esac
	seen="$seen $user"
	clean_user "$user"
done

echo "==== ucm da7219 ===="
alsaucm -c hw:DA7219 dump text | head -20
echo "==== ucm max98357a ===="
alsaucm -c hw:MAX98357A dump text | head -15
echo "==== installed ===="
readlink -f "$UCM/conf.d/avs_da7219/avs_da7219.conf"
readlink -f "$UCM/conf.d/avs_max98357a/avs_max98357a.conf"
echo /etc/wireplumber/wireplumber.conf.d/akali-audio.conf
