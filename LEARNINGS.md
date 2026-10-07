# Learnings


## WSL install failed: "virtualization is not enabled"
- Check: the PowerShell command for VirtualizationFirmwareEnabled printed False.
- Fix: turned on virtualization (SVM Mode) in the BIOS. The same command then printed True and the install worked.
- Lesson: test the underlying requirement before reinstalling anything.

## Ubuntu setup window hung on "Waiting for OOBE command"
- Cause: the username prompt was in the PowerShell window where I ran the install command, not in the Ubuntu app.
- Lesson: input prompts appear in the window that launched the command.

## Terminal stuck at a ">" prompt
- Cause: a stray backtick copied with a command left a quote unclosed.
- Fix: Ctrl+C cancels it. Type commands by hand when copying fails.

## "docker: command not found" in Ubuntu
- Cause: Docker Desktop's WSL integration was off for Ubuntu.
- Fix: Settings > Resources > WSL integration, turned on the Ubuntu toggle, then Apply.