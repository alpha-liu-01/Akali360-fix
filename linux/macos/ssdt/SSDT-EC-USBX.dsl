DefinitionBlock ("", "SSDT", 2, "AKALI", "ECUSBX", 0x00000000)
{
    External (_SB_.PCI0.LPCB, DeviceObj)

    Scope (\_SB.PCI0.LPCB)
    {
        Device (EC)
        {
            Name (_HID, "ACID0001")
            Method (_STA, 0, NotSerialized)
            {
                If (_OSI ("Darwin"))
                {
                    Return (0x0F)
                }

                Return (Zero)
            }
        }
    }

    Scope (\_SB)
    {
        Device (USBX)
        {
        Name (_ADR, Zero)
        Method (_DSM, 4, NotSerialized)
        {
            If ((Arg2 == Zero))
            {
                Return (Buffer (One)
                {
                     0x03
                })
            }

            If (_OSI ("Darwin"))
            {
                Return (Package (0x08)
                {
                    "kUSBSleepPowerSupply",
                    0x13EC,
                    "kUSBSleepPortCurrent",
                    0x0834,
                    "kUSBWakePowerSupply",
                    0x13EC,
                    "kUSBWakePortCurrent",
                    0x0834
                })
            }

            Return (Buffer (One)
            {
                 0x00
            })
        }
        }
    }
}
