param (

    [Parameter(Mandatory = $true)]

    [String]$EndUserMachine

)

#Make the information for the MessageBox

[System.String]$Title = "Teams Self Repair"

[System.String]$Message = "Would you like to proceed with your requested Teams Self-Repair? This will shut down your teams client, and should only take a few minutes."

[int]$Duration = 30

#Confirm conection to machine

 

if (!(Test-Connection -ComputerName $EndUserMachine -Count 2)) {

    throw "Failed to connect to endpoint."

}

 

#Invoke command against remote machine

Try {

    Invoke-Command -ComputerName $EndUserMachine -ScriptBlock {

        #Assign args to vars for ease of reading

        $Title = $args[0]

        $Message = $args[1]

        $Duration = $args[2]

        $Style = 0x00000004L

        #Create C# for message box

        $typeDefinition = @"

        using System;

        using System.Runtime.InteropServices;

 

        public class WTSMessage {

            [DllImport("wtsapi32.dll", SetLastError = true)]

            public static extern bool WTSSendMessage(

                IntPtr hServer,

                [MarshalAs(UnmanagedType.I4)] int SessionId,

                String pTitle,

                [MarshalAs(UnmanagedType.U4)] int TitleLength,

                String pMessage,

                [MarshalAs(UnmanagedType.U4)] int MessageLength,

                [MarshalAs(UnmanagedType.U4)] int Style,

                [MarshalAs(UnmanagedType.U4)] int Timeout,

                [MarshalAs(UnmanagedType.U4)] out int pResponse,

                bool bWait

            );

 

            static int response = 0;

 

            public static int SendMessage(int SessionID, String Title, String Message, int Timeout, int MessageBoxType) {

                WTSSendMessage(IntPtr.Zero, SessionID, Title, Title.Length, Message, Message.Length, MessageBoxType, Timeout, out response, true);

 

                return response;

            }

        }

"@

       

        #Make sure WTS message type exists, if not, add it

        if (-not ([System.Management.Automation.PSTypeName]'WTSMessage').Type) {

            Add-Type -TypeDefinition $typeDefinition

        }

        #Query all current user sessions

        $RawOuput = (quser) -replace '\s{2,}', ',' | ConvertFrom-Csv

        $sessionID = $null

        $UserAccount = $null

        #Get the session ID we'll need, as well as the username of the user

        Foreach ($session in $RawOuput) {

            if (($session.sessionname -notlike "console") -AND ($session.sessionname -notlike "rdp-tcp*")) {

                if ($session.ID -eq "Active") {

                    $sessionID = $session.SESSIONNAME

                    $Useraccount = $Session.USERNAME

                }

            }

            else {

                if ($session.STATE -eq "Active") {

                    $sessionID = $session.ID

                    $Useraccount = $Session.USERNAME

                }

            }

        }

        #Ask the user if we can continue

        $Messageresponse = [WTSMessage]::SendMessage($sessionID, $title, $message, $duration, $style)

        #Some users have a > in their username, remove it if its found

        if ($UserAccount -like "*>*") { $UserAccount = $Useraccount.Replace(">", "") }

        #If user said yes

        if ($Messageresponse -eq 6) {

            Write-Output "I should preform actions here"

            #Get and stop all Teams processes

            $TeamsProcesses = Get-Process | where { $_.ProcessName -like "*Teams*" }

            foreach ($Process in $TeamsProcesses) {

                Stop-Process -Id $Process.ID -Force -Confirm:$false

            }

            #Remove the cache folder

            Write-Output "I should delete C:\Users\$UserAccount\AppData\Roaming\Microsoft\Teams\Cache"

            Try {

                Remove-Item -Path "C:\Users\$UserAccount\AppData\Roaming\Microsoft\Teams\Cache" -Force -Recurse

            }

            catch {

                Write-Output "Failed to remove cache folder"

            }

            #Alert the user that we are done and they can re-open teams

            [WTSMessage]::SendMessage($sessionID, $title, "Self-repair complete! You may now open your Teams client once again. If your issue persists, please open a ticket. Thank you!", $duration, 0x00000000L)

        }

        #If response is not a return code of 6, it either timed out or they said no, so don't do anything

        else {

            throw "User said no!"

        }

    } -ArgumentList $Title, $Message, $Duration

}

catch {

    throw "Failed to invoke-command against remote computer."

}