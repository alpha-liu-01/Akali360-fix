DefinitionBlock ("", "SSDT", 2, "AKALI", "PLUG", 0x00000000)
{
    External (_SB_.CP00, DeviceObj)

    Scope (\_SB.CP00)
    {
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
                Return (Package (0x02)
                {
                    "plugin-type",
                    One
                })
            }

            Return (Buffer (One)
            {
                 0x00
            })
        }
    }
}
