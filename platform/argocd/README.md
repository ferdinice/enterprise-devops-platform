# ArgoCD Platform Toolkit

## Purpose

This toolkit installs, verifies, and removes ArgoCD from the Kubernetes platform.

ArgoCD provides GitOps-based application delivery by continuously comparing the desired state stored in Git with the actual state running in Kubernetes.

## Architecture

```text
Git repository
      ↓
ArgoCD Repo Server
      ↓
Application Controller
      ↓
Kubernetes API
      ↓
Application workloads