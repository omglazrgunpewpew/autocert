# Backups Directory

This directory contains backup files and development artifacts that are excluded from Git tracking.

## Contents

### Main.ps1 Versions
- `Main-Original-Backup.ps1` - Original 1,280-line version before refactoring
- `Main-Refactored.ps1` - Template used for the refactoring process

## Purpose

These files are preserved locally for:
- **Recovery**: In case the refactored version needs to be reverted
- **Reference**: To compare old vs new implementations
- **Documentation**: To track the evolution of the codebase

## Git Exclusion

This directory is excluded from Git tracking via `.gitignore` to:
- Keep the repository clean and focused
- Avoid committing large legacy files
- Prevent sensitive or temporary data from being synced
- Maintain a professional project structure

## Maintenance

- Backup files can be safely deleted if no longer needed
- Consider archiving very old backups periodically
- New backup files should be placed in this directory

---
*This directory is automatically excluded from Git tracking and OneDrive sync.*
