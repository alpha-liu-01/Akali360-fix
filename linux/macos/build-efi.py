#!/usr/bin/env python3
"""Assemble ~/akali-macos/efi from the pinned zips and the SSDTs in this directory.

Does not touch the microSD, NVRAM, or the internal eMMC.
"""
import json
import plistlib
import shutil
import struct
import subprocess
import zipfile
from pathlib import Path

HOME = Path.home()
ROOT = HOME / "akali-macos"
SRC = ROOT / "src"
OC = ROOT / "unpack"
EFI_ROOT = ROOT / "efi" / "EFI"
KEXT_STAGE = ROOT / "kexts"
ACPI_OUT = ROOT / "acpi"
SSDT_DIR = Path(__file__).resolve().parent / "ssdt"
IASL = HOME / "akali-macos/tools/debs/extracted/usr/bin/iasl"
MACSERIAL = OC / "Utilities/macserial/macserial.linux"
SAMPLE = OC / "Docs/Sample.plist"
OCVALIDATE = OC / "Utilities/ocvalidate/ocvalidate.linux"
SMBIOS_PATH = ROOT / "smbios.json"
NVRAM = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
WIFI_ROM = bytes.fromhex("dc71964f3e9f")

# Order is load order. Lilu first. No SMCBatteryManager on the first boot.
KEXTS = [
    ("Lilu-1.7.2-RELEASE.zip", "Lilu.kext", "", ""),
    ("VirtualSMC-1.3.8-RELEASE.zip", "VirtualSMC.kext", "", ""),
    ("WhateverGreen-1.7.1-RELEASE.zip", "WhateverGreen.kext", "", ""),
    ("AppleALC-1.9.8-RELEASE.zip", "AppleALC.kext", "", ""),
    ("RestrictEvents-1.1.6-RELEASE.zip", "RestrictEvents.kext", "", ""),
    ("USBToolBox-1.2.0-RELEASE.zip", "USBToolBox.kext", "", ""),
    ("VoodooPS2Controller-2.3.7-RELEASE.zip", "VoodooPS2Controller.kext", "", ""),
    (
        "AirportItlwm-Sequoia-v2.4.0-RELEASE-alpha-7204c69.zip",
        "AirportItlwm.kext",
        "24.0.0",
        "24.99.99",
    ),
]

# ACPI name, macOS port number, UsbConnector.
# 255 internal, 3 USB Type-A, 9 USB Type-C.
# HS05 bluetooth, HS07 camera, SS04 Genesys card reader.
PORTS = [
    ("HS01", 1, 3),
    ("HS02", 2, 3),
    ("HS03", 3, 3),
    ("HS04", 4, 3),
    ("HS05", 5, 255),
    ("HS06", 6, 3),
    ("HS07", 7, 255),
    ("HS08", 8, 3),
    ("HS09", 9, 3),
    ("HS10", 10, 3),
    ("USR1", 11, 9),
    ("USR2", 12, 9),
    ("SS01", 13, 3),
    ("SS02", 14, 3),
    ("SS03", 15, 3),
    ("SS04", 16, 255),
    ("SS05", 17, 3),
    ("SS06", 18, 3),
]


def top_kexts(root: Path):
    found = []
    for path in root.rglob("*.kext"):
        if any(parent.name.endswith(".kext") for parent in path.parents):
            continue
        if (path / "Contents" / "Info.plist").is_file():
            found.append(path)
    return found


def stage_kexts():
    if KEXT_STAGE.exists():
        shutil.rmtree(KEXT_STAGE)
    KEXT_STAGE.mkdir(parents=True)
    staged = {}
    for zip_name, kext_name, _min, _max in KEXTS:
        dest = KEXT_STAGE / zip_name.replace(".zip", "")
        dest.mkdir()
        with zipfile.ZipFile(SRC / zip_name) as archive:
            archive.extractall(dest)
        matches = [path for path in top_kexts(dest) if path.name == kext_name]
        if len(matches) != 1:
            names = [path.name for path in top_kexts(dest)]
            raise SystemExit(f"{zip_name}: wanted {kext_name}, found {names}")
        staged[kext_name] = matches[0]
    plugins = staged["VoodooPS2Controller.kext"] / "Contents" / "PlugIns"
    for name in ("VoodooPS2Mouse.kext", "VoodooPS2Trackpad.kext"):
        path = plugins / name
        if path.exists():
            shutil.rmtree(path)
    return staged


def compile_ssdt():
    if ACPI_OUT.exists():
        shutil.rmtree(ACPI_OUT)
    ACPI_OUT.mkdir()
    for source in sorted(SSDT_DIR.glob("*.dsl")):
        subprocess.run(
            [str(IASL), "-ve", "-p", str(ACPI_OUT / source.stem), str(source)],
            check=True,
        )
        aml = ACPI_OUT / f"{source.stem}.aml"
        if not aml.is_file():
            raise SystemExit(f"iasl did not write {aml}")


def utbmap():
    ports = {}
    for name, number, connector in PORTS:
        ports[name] = {
            "UsbConnector": connector,
            "port": struct.pack("<I", number),
        }
    plist = {
        "CFBundleDevelopmentRegion": "English",
        "CFBundleIdentifier": "com.dhinakg.USBToolBox.map",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "UTBMap",
        "CFBundlePackageType": "KEXT",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1.0",
        "OSBundleRequired": "Root",
        "OSBundleLibraries": {"com.dhinakg.USBToolBox.kext": "1.0.0"},
        "IOKitPersonalities": {
            "8086_9d2f": {
                "CFBundleIdentifier": "com.dhinakg.USBToolBox.kext",
                "IOClass": "USBToolBox",
                "IOProviderClass": "IOPCIDevice",
                "IOMatchCategory": "USBToolBox",
                "IOPCIPrimaryMatch": "0x9d2f8086",
                "IOProviderMergeProperties": {
                    "ports": ports,
                    "port-count": struct.pack("<I", 18),
                },
            }
        },
    }
    bundle = KEXT_STAGE / "UTBMap.kext" / "Contents"
    bundle.mkdir(parents=True)
    with (bundle / "Info.plist").open("wb") as handle:
        plistlib.dump(plist, handle)


def smbios():
    # Macmini8,1 is a Sequoia-native Mac with no T2 chip. MacBookPro15,2
    # makes AppleKeyStore wait on a Secure Enclave this board does not have.
    if SMBIOS_PATH.is_file():
        saved = json.loads(SMBIOS_PATH.read_text())
        if saved.get("SystemProductName") == "Macmini8,1":
            return saved
    out = subprocess.check_output(
        [str(MACSERIAL), "-m", "Macmini8,1", "-n", "1", "-g"], text=True
    )
    serial = mlb = None
    for line in out.splitlines():
        parts = [part.strip() for part in line.split("|")]
        parts = [part for part in parts if part]
        if len(parts) >= 3 and parts[0] == "Macmini8,1":
            serial, mlb = parts[1], parts[2]
            break
        if len(parts) == 2 and parts[0].startswith("C07"):
            serial, mlb = parts
            break
    if not serial or not mlb:
        raise SystemExit(f"macserial output was not understood:\n{out}")
    uuid = subprocess.check_output(["uuidgen"], text=True).strip().upper()
    data = {
        "SystemProductName": "Macmini8,1",
        "SystemSerialNumber": serial,
        "MLB": mlb,
        "SystemUUID": uuid,
        "ROM": WIFI_ROM.hex(),
    }
    SMBIOS_PATH.write_text(json.dumps(data, indent=2) + "\n")
    return data


def kext_entry(name, executable, min_kernel, max_kernel):
    return {
        "Arch": "Any",
        "BundlePath": name,
        "Comment": "",
        "Enabled": True,
        "ExecutablePath": executable,
        "MaxKernel": max_kernel,
        "MinKernel": min_kernel,
        "PlistPath": "Contents/Info.plist",
    }


def build_config(identity):
    with SAMPLE.open("rb") as handle:
        config = plistlib.load(handle)
    config["ACPI"]["Add"] = [
        {"Comment": path.name, "Enabled": True, "Path": path.name}
        for path in sorted(ACPI_OUT.glob("*.aml"))
    ]
    entries = []
    for _zip, name, min_kernel, max_kernel in KEXTS:
        if name == "USBToolBox.kext":
            entries.append(kext_entry(name, "Contents/MacOS/USBToolBox", "", ""))
            entries.append(kext_entry("UTBMap.kext", "", "", ""))
            continue
        binary = name.replace(".kext", "")
        entry = kext_entry(name, f"Contents/MacOS/{binary}", min_kernel, max_kernel)
        # The 7265 driver can stall IOKit start. The installer can use USB tethering.
        if name == "AirportItlwm.kext":
            entry["Enabled"] = False
        entries.append(entry)
    config["Kernel"]["Add"] = entries
    quirks = config["Kernel"]["Quirks"]
    quirks["AppleCpuPmCfgLock"] = False
    quirks["AppleXcpmCfgLock"] = True
    quirks["DisableIoMapper"] = True
    quirks["DisableIoMapperMapping"] = False
    quirks["PanicNoKextDump"] = True
    quirks["PowerTimeoutKernelPanic"] = True
    quirks["XhciPortLimit"] = False
    booter = config["Booter"]["Quirks"]
    booter["AvoidRuntimeDefrag"] = True
    # Chrultrabook: this quirk breaks runtime EFI services on MrChromebox.
    booter["DevirtualiseMmio"] = False
    booter["EnableSafeModeSlide"] = True
    booter["EnableWriteUnprotector"] = False
    booter["FixupAppleEfiImages"] = True
    booter["ProtectUefiServices"] = True
    booter["ProvideCustomSlide"] = True
    booter["RebuildAppleMemoryMap"] = True
    booter["SetupVirtualMap"] = False
    booter["SyncRuntimePermissions"] = True
    boot = config["Misc"]["Boot"]
    boot["LauncherOption"] = "Disabled"
    boot["ShowPicker"] = True
    boot["Timeout"] = 5
    boot["PickerMode"] = "Builtin"
    boot["HibernateMode"] = "None"
    boot["HideAuxiliary"] = False
    security = config["Misc"]["Security"]
    security["SecureBootModel"] = "Disabled"
    security["ScanPolicy"] = 0
    security["Vault"] = "Optional"
    # DEBUG_ERROR is 0x80000000. The sample value halts on every such line,
    # including a missing optional driver.
    security["HaltLevel"] = 0
    if "DmgLoading" in security:
        security["DmgLoading"] = "Any"
    debug = config["Misc"]["Debug"]
    debug["Target"] = 0x43
    debug["DisableWatchDog"] = True
    debug["ApplePanic"] = True
    nvram = config["NVRAM"]["Add"][NVRAM]
    # Sequoia has no Kaby Lake graphics driver. Leave the firmware framebuffer up.
    nvram["boot-args"] = "-v keepsyms=1 debug=0x100 -igfxvesa -wegnoigpu"
    nvram["prev-lang:kbd"] = b"zh-Hans:252\0"
    config["PlatformInfo"]["Automatic"] = True
    config["PlatformInfo"]["UpdateSMBIOSMode"] = "Custom"
    generic = config["PlatformInfo"]["Generic"]
    generic["SystemProductName"] = identity["SystemProductName"]
    generic["SystemSerialNumber"] = identity["SystemSerialNumber"]
    generic["MLB"] = identity["MLB"]
    generic["SystemUUID"] = identity["SystemUUID"]
    generic["ROM"] = bytes.fromhex(identity["ROM"])
    generic["SpoofVendor"] = True
    config["DeviceProperties"]["Add"].pop("PciRoot(0x0)/Pci(0x2,0x0)", None)
    # AppleACPIEC binds PNP0C09 and can sit on the Chrome EC with no further log.
    # 09 0C D0 41 is EisaId("PNP0C09").
    ec_patch = dict(config["ACPI"]["Patch"][0])
    ec_patch.update(
        {
            "Base": "",
            "BaseSkip": 0,
            "Comment": "Chrome EC is not an Apple EC",
            "Count": 0,
            "Enabled": True,
            "Find": bytes.fromhex("090cd041"),
            "Limit": 0,
            "Mask": b"",
            "OemTableId": b"",
            "Replace": bytes.fromhex("090cd042"),
            "ReplaceMask": b"",
            "Skip": 0,
            "TableLength": 0,
            "TableSignature": b"",
        }
    )
    config["ACPI"]["Patch"].append(ec_patch)
    uefi = config["UEFI"]["Quirks"]
    uefi["ReleaseUsbOwnership"] = True
    uefi["RequestBootVarRouting"] = True
    # MrChromebox still applies an image security policy with Secure Boot off.
    # LoadImage then rejects OpenRuntime.efi with EFI_INVALID_PARAMETER.
    uefi["DisableSecurityPolicy"] = True
    for driver in config["UEFI"]["Drivers"]:
        if driver["Path"] == "HfsPlus.efi":
            # The release zip ships OpenHfsPlus.efi, not Apple's HfsPlus.efi.
            driver["Path"] = "OpenHfsPlus.efi"
            driver["Enabled"] = True
        if driver["Path"] == "ResetNvramEntry.efi":
            driver["Enabled"] = True
        if driver["Path"] == "Ps2KeyboardDxe.efi":
            # MrChromebox already provides the PS/2 keyboard.
            driver["Enabled"] = False
        if driver["Path"] == "OpenLinuxBoot.efi":
            driver["Enabled"] = False
    if "Resolution" in config["UEFI"]["Output"]:
        # 2256x1504. Keep the firmware mode instead of the highest GOP mode.
        config["UEFI"]["Output"]["Resolution"] = ""
    apfs = config["UEFI"].get("APFS", {})
    for key in ("MinDate", "MinVersion"):
        if key in apfs and apfs[key] not in (0, -1):
            apfs[key] = -1
    path = EFI_ROOT / "OC" / "config.plist"
    with path.open("wb") as handle:
        plistlib.dump(config, handle)
    return path


def assemble():
    source_efi = OC / "X64" / "EFI"
    if not (source_efi / "OC" / "OpenCore.efi").is_file():
        raise SystemExit(f"missing {source_efi}")
    if EFI_ROOT.exists():
        shutil.rmtree(EFI_ROOT)
    shutil.copytree(source_efi, EFI_ROOT)
    staged = stage_kexts()
    utbmap()
    kext_dir = EFI_ROOT / "OC" / "Kexts"
    for name in [item[1] for item in KEXTS] + ["UTBMap.kext"]:
        source = staged.get(name, KEXT_STAGE / name)
        shutil.copytree(source, kext_dir / name)
    compile_ssdt()
    acpi_dir = EFI_ROOT / "OC" / "ACPI"
    for aml in ACPI_OUT.glob("*.aml"):
        shutil.copy2(aml, acpi_dir / aml.name)
    identity = smbios()
    config_path = build_config(identity)
    subprocess.run([str(OCVALIDATE), str(config_path)], check=True)
    print("efi", EFI_ROOT)
    print("serial", identity["SystemSerialNumber"])
    print("mlb", identity["MLB"])


if __name__ == "__main__":
    assemble()
