# Linux Fundamentals

## Introduction

Linux is an open-source operating system widely used in cloud computing, DevOps, and enterprise environments. Most cloud platforms, including AWS, Azure, and Google Cloud, rely heavily on Linux because of its stability, security, performance, and flexibility.

As a DevOps Engineer, understanding Linux is essential because web servers, databases, Docker containers, Kubernetes clusters, and CI/CD tools commonly run on Linux.

---

# Computer Architecture

A computer consists of four major components that work together to execute applications.

## CPU (Central Processing Unit)

The CPU is the brain of the computer. It executes instructions, performs calculations, and processes tasks requested by the operating system and applications.

Responsibilities include:

- Executing program instructions
- Performing arithmetic and logical operations
- Managing process execution

---

## RAM (Random Access Memory)

RAM is temporary memory used to store data that is actively being used by running applications.

Characteristics:

- Very fast
- Volatile (data is lost when power is removed)
- Stores running programs and active data

When RAM becomes full, Linux may begin using swap space, which is much slower than RAM and can reduce system performance.

---

## Storage

Storage is permanent memory where files, applications, and the operating system are stored.

Examples include:

- SSD
- HDD

Unlike RAM, storage retains data after the computer is powered off.

---

# Operating System

The operating system manages communication between applications and hardware.

Its responsibilities include:

- Process management
- Memory management
- File system management
- Device management
- Security and user management

Applications do not communicate directly with hardware. Instead, they request services from the operating system through system calls.

---

# Linux Kernel

The Linux kernel is the core component of the operating system.

It is responsible for:

- CPU scheduling
- Memory allocation
- Hardware communication
- Process management
- Device drivers
- File system management

Every application running on Linux ultimately depends on the kernel.

---

# User Space and Kernel Space

Linux separates application execution into two environments.

## User Space

Applications such as:

- Chrome
- Jenkins
- Docker
- Nginx

run in user space.

Applications cannot directly access hardware.

---

## Kernel Space

Kernel space has unrestricted access to hardware resources.

When an application needs hardware resources such as files, memory, or networking, it makes a system call to the kernel.

This separation improves system stability and security.

---

# Linux Processes

A process is a running instance of a program.

Each process has:

- Process ID (PID)
- Memory allocation
- CPU time
- Open files
- Threads

The operating system schedules processes to share CPU resources efficiently.

---

# Threads

A thread is the smallest unit of execution within a process.

Multiple threads can exist inside a single process while sharing the same memory and resources.

Example:

A web browser can have separate threads for:

- Rendering webpages
- Playing videos
- Downloading files

---

# Important Process States

Running (R)
- Currently executing on the CPU.

Sleeping (S)
- Waiting for an event such as user input, disk activity, or network traffic.

Uninterruptible Sleep (D)
- Waiting for disk or I/O operations.

Zombie (Z)
- Process has finished execution but its parent has not collected its exit status.

Orphan
- A child process whose parent has terminated. It is adopted by PID 1 (systemd).

---

# Essential Linux Troubleshooting Commands

| Command | Purpose | DevOps Use Case |
|---------|----------|-----------------|
| top | Monitor CPU, memory, and running processes | First command during incident response |
| ps aux | Display running processes | Identify resource-consuming processes |
| free -h | Display memory usage | Investigate RAM exhaustion |
| df -h | Display disk usage | Detect full filesystems |
| vmstat | Display system performance statistics | Quick health overview |
| iostat | Display disk I/O statistics | Diagnose storage bottlenecks |
| iotop | Show processes using disk I/O | Identify heavy disk users |
| lsof | List open files and ports | Identify processes using files or network ports |
| pstree | Display parent-child process hierarchy | Understand process relationships |

---

# Summary

Linux forms the foundation of modern DevOps engineering.

Understanding Linux processes, memory management, the kernel, and troubleshooting tools enables engineers to diagnose production issues, automate infrastructure, and operate cloud-native applications efficiently.