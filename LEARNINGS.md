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

## Terminal frozen in "Select" mode
- Symptom: Ctrl+C did nothing and the server kept running.
- Cause: the Ubuntu window was in text-selection mode ("Select" in the title bar).
- Fix: Esc, then Ctrl+C. If still stuck, wsl --shutdown from PowerShell.

## VS Code lost its connection to Ubuntu
- Cause: wsl --shutdown stopped the Linux side VS Code was connected to.
- Fix: close the window and run code . from Ubuntu.

## Folder created with a stray apostrophe
- Symptom: cd infra/bootstrap failed even though VS Code showed the folder.
- Diagnosis: ls showed infra' with a stray quote. Fixed with mv ./*infra* infra.
- Lesson: create folders from the terminal and check names with ls.

## Two .gitignore files
- Cause: Python venv creates its own .gitignore inside .venv, and I edited that one.
- Fix: edit the repo-level file. git check-ignore -v <path> proves a rule matches.

## Reading a Terraform plan before answering apply
- A name line with "forces replacement" means destroy and recreate.
- Terraform holds the state lock while an apply waits at the yes/no prompt.

## Terraform drift and renames
- Changed a parameter in the console. plan showed the drift, and apply restored it.
- Renaming a resource label plans destroy plus create. A moved block makes it a state-only change.