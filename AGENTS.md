# EqManager Workspace Rules

- **Always deploy changes for testing:** Whenever you make code changes that need to be tested or reviewed in-game, automatically run `powershell.exe -ExecutionPolicy Bypass -File .\deploy.ps1` from the repository root before asking the user to test or reload their UI.
