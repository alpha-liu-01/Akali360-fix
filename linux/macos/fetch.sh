#!/bin/sh
# Download the pinned macOS 15 installer inputs into ~/akali-macos/src.
# Checksums are the files fetched on 2026-11-07.
set -eu
dest="${HOME}/akali-macos/src"
mkdir -p "$dest"
cd "$dest"

fetch() {
	url=$1
	out=$2
	sum=$3
	if [ -f "$out" ]; then
		echo "$sum  $out" | sha256sum -c -
		return
	fi
	curl -fL --retry 3 --retry-delay 2 -o "$out.part" "$url"
	mv "$out.part" "$out"
	echo "$sum  $out" | sha256sum -c -
}

fetch "https://github.com/acidanthera/OpenCorePkg/releases/download/1.0.8/OpenCore-1.0.8-RELEASE.zip" \
	OpenCore-1.0.8-RELEASE.zip \
	2011e8b7216ecb2645d97ea710df965947edd406846e92050b9bc4190be6d27b
fetch "https://github.com/acidanthera/Lilu/releases/download/1.7.2/Lilu-1.7.2-RELEASE.zip" \
	Lilu-1.7.2-RELEASE.zip \
	53967d7dcfaab01023a33df2e969a89522f13d6654a6a56ac4711b62dabf3ab8
fetch "https://github.com/acidanthera/VirtualSMC/releases/download/1.3.8/VirtualSMC-1.3.8-RELEASE.zip" \
	VirtualSMC-1.3.8-RELEASE.zip \
	2e29a8aaf91b4eb0bcdf5913ed17e70f5cf76531122acd4132eff7813a54de8b
fetch "https://github.com/acidanthera/WhateverGreen/releases/download/1.7.1/WhateverGreen-1.7.1-RELEASE.zip" \
	WhateverGreen-1.7.1-RELEASE.zip \
	1bfdd2d40290ecce237606db121cbc01d7041179f03394bd59660a2ed52e5c95
fetch "https://github.com/acidanthera/AppleALC/releases/download/1.9.8/AppleALC-1.9.8-RELEASE.zip" \
	AppleALC-1.9.8-RELEASE.zip \
	d4d36cd2da7863cf7cbfcb0892d45c08457f4f4ddd065a073dd010e46bd63bcb
fetch "https://github.com/acidanthera/RestrictEvents/releases/download/1.1.6/RestrictEvents-1.1.6-RELEASE.zip" \
	RestrictEvents-1.1.6-RELEASE.zip \
	98170dfae195ddd28b5d95e3f040125a13ca783bcb9bd1e5b8c588e217b14ee6
fetch "https://github.com/acidanthera/VoodooPS2/releases/download/2.3.7/VoodooPS2Controller-2.3.7-RELEASE.zip" \
	VoodooPS2Controller-2.3.7-RELEASE.zip \
	d5483298736ba4b3b82c7203d9a46968c668fb7af732b8b22c2096deb0acf83f
fetch "https://github.com/USBToolBox/kext/releases/download/1.2.0/USBToolBox-1.2.0-RELEASE.zip" \
	USBToolBox-1.2.0-RELEASE.zip \
	c315a3a5acfd496dd97d0d19b4fbd1d487103d2fd541c5651583d4c9cebcfe07
fetch "https://github.com/1Revenger1/ECEnabler/releases/download/1.0.6/ECEnabler-1.0.6-RELEASE.zip" \
	ECEnabler-1.0.6-RELEASE.zip \
	e21149519856308c6c4c06e0917aef9e3423ff3e23b6ea77989099f4f2cf0f0a
fetch "https://github.com/laobamac/itlwm/releases/download/v2.4.0-alpha/AirportItlwm-Sequoia-v2.4.0-RELEASE-alpha-7204c69.zip" \
	AirportItlwm-Sequoia-v2.4.0-RELEASE-alpha-7204c69.zip \
	263d35e5954808f43bde17b9695b675aefc2f6d4cded71306b1b6575aea61a82
