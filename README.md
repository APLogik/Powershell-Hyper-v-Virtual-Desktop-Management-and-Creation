# PowerShell Script for Managing VDI Machines

I wrote this script to automate some management tasks on a Hyper-V based virtual desktop pool. It provides various functions for creating, replacing, and managing VDI machines in a domain environment. This script is specifically designed for a virtual machine pool type RDSH setup, aiming to execute tasks efficiently across a large number of machines.  This is limited to running jobs against one host at a time, but you can run this script in more than one window to manage multiple hosts/machines at the same time.

## Prerequisites

Before running the script, ensure that the following requirements are met:

- Hyper-V, Active Directory, and Remote Desktop Session Host PowerShell plugins may need to be installed.
- The machine running the script can communicate with the IP addresses of the VDI machines, the VDI host machines, and the RDSH (Remote Desktop Session Host) manager server.
- A uniform naming convention is used for VDI machines with a prefix and a unique four-digit number.
- You have already created a base image VHDX and associated a blank diffdisk with it. During machine creation, this diffdisk is copied and renamed, and new machines' VHDX files only contain changed information.
- You have an RDSH pool running, with at least one session manager and one hyper-v host.
- You are signed in and running powershell with an account that has permissions to do everything in the script.  (managing RDSH, joining to the domain, managing hyper-v hosts)

## Functionality Overview

The script provides the following menu-driven functions:

1. **Manage Existing Machines**

   This function allows you to perform various actions on existing VDI machines, such as:
   - NotifyUsers: Notifies logged-in users.
   - Reboot: Reboots selected VDI machines.
   - Shutdown: Shuts down selected VDI machines.
   - Save: Saves selected VDI machines.
   - LogOff: Logs off users from selected VDI machines.
   - ChangeHardware: Changes hardware settings on selected machines.
   - JoinDomain: Joins machines to the domain.
   - RenameAndJoinDomain: Renames and joins machines to the domain.
   - RemoveFromPool: Removes VDI machines from the pool.
   - RemoveVDIAssignment: Removes VDI machine assignments.
   - RemoveVDIAssignments-ThatAreLoggedOff: Removes VDI assignments where there are no active or disconnected connections.
   
   This menu serves as a scaffold to add or customize common tasks you might want to perform on large numbers of Hyper-V machines.

   The workflow for managing existing machines in the script is as follows:
   - Choose a menu option for the desired script action.
   - Answer prompts regarding sending notifications to users.
   - Answer prompts regarding delaying notifications or actions.
   - Choose a starting machine number.
   - Specify the number of machines to target (counting up from the previous number).
   - Set the Hyper-V host on which the machines are located.
   - The script presents the chosen parameters and prompts for confirmation.
   - Delays and notifications are processed.
   - If credentials are needed, you are prompted to enter them.
   - The selected action is taken without breaking it into chunks.
 

2. **Create or Replace VDI Machines**

   This function creates or replaces VDI machines.
   - To avoid host overload situations, this function splits large jobs into batches for machine creation.
   - At the top of the script, there are many variables that need to be customized for your preferences and environment.

   The workflow for creating or replacing machines in the script is as follows:
   - You are prompted for domain and local admin credentials.
   - Choose a starting machine number.
   - Specify the number of machines to target (counting up from the previous number).
   - Set the Hyper-V host on which the machines are located.
   - The script presents the chosen parameters and prompts for confirmation.
   - The script builds, renames, domain joins, and adds machines to the pool. There are a few pauses and prompts between phases that are configurable depending on preference.  It is possible to start this script and configure the pauses so that the entire build process is hands-free.

Please note that the script requires domain credentials for joining machines to the domain and local admin credentials for target machines.

It's essential to review the script and customize the parameters according to your environment before running it.
