# MDM Deployment Guide: `backup_restore_vmdirectory.sh`

## Overview

Deploy two Jamf Pro policies for this script. Instructions apply equally to Mosyle, Kandji, or Intune — adapt policy and trigger names accordingly.

| Policy | Trigger | Purpose |
|---|---|---|
| **PD-VM-Backup** | Recurring check-in | Keeps the VM list backup current as users add/remove VMs |
| **PD-VM-Restore** | Login | Re-registers VMs automatically after Migration Assistant |

---

## Setup

Upload the script to Jamf Pro under **Settings → Computer Management → Scripts**:

- **Name:** `backup_restore_vmdirectory`
- **Priority:** `After`
- **Scope (both policies):** Smart Group matching `Parallels Desktop installed`

---

## Policy 1 — Recurring Backup

| Field | Value |
|---|---|
| **Name** | `PD - VM Directory Backup` |
| **Trigger** | `Recurring Check-In` |
| **Execution Frequency** | `Once every day` |
| **Script** | `backup_restore_vmdirectory` |
| **Run As** | `root` |

---

## Policy 2 — Restore on Login

| Field | Value |
|---|---|
| **Name** | `PD - VM Directory Restore on Login` |
| **Trigger** | `Login` |
| **Execution Frequency** | `Once per computer` |
| **Script** | `backup_restore_vmdirectory` |
| **Run As** | `root` |

> The restore runs only when Parallels preferences are absent — it skips silently on machines where Parallels is already configured.

---

## Migration Assistant Workflow

1. **Before migration:** the daily backup policy ensures `/Users/Shared/Parallels/` on the source Mac is current.
2. **Migration Assistant** copies `/Users/Shared/Parallels/` to the target Mac along with the rest of the user data.
3. **On first login** on the target Mac, the restore policy fires and re-registers all VMs with Parallels Desktop automatically — no user action required.
