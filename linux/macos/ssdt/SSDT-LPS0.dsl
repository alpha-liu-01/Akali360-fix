DefinitionBlock ("", "SSDT", 2, "AKALI", "LPS0", 0x00000000)
{
    Scope (\_SB)
    {
        Method (LPS0, 0, NotSerialized)
        {
            If (_OSI ("Darwin"))
            {
                Return (One)
            }

            Return (Zero)
        }
    }
}
