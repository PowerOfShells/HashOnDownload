# HashOnDownload
Monitors the download folder, calculates the hashes and pushes a toast notification to the user

For now only works with Windows & Powershell 5.1, Desktop Edition

# Get started

After download just place all files where you want them to be.
Just start a `powershell`there (`Shift + Rightclick -> Start Powershell here ...` ) and type `& .\HashOnDownload.ps1`

Done! The daemon is up and running and you can even see what he is doing. Neat!
Dont like console windows being open all the time? *I mean, who does ...*
No problem! Just call the script as described above with the -EnableAutorun param.

`.\HashonDownload.ps1 -enableAutorun`

It will add a "run" registry key for your user, which tells Windows to run the script on logon.
So now after restarting or just logging out & in again, the daemon will run hidden (*...just a slight glimpse of a powershell for half a second, cant fix that for now*)
and you are good to go and trust those downloads on the internet, provided there are file hashes present on the website.


Let me know if you run into issues.
