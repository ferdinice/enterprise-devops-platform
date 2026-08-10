# Monitoring Toolkit

This directory contains the monitoring stack for the Enterprise DevOps Platform.

The monitoring stack is deployed with the Prometheus Community Helm chart:

`kube-prometheus-stack`

## Components

The stack includes:

- Prometheus
- Grafana
- kube-state-metrics
- node-exporter
- Prometheus Operator

Alertmanager is currently disabled to keep the implementation focused and cost-efficient.

## Purpose

The monitoring stack provides visibility into:

- Kubernetes node health
- Pod health
- CPU usage
- Memory usage
- Deployment status
- Kubernetes object state
- Cluster resource utilization

## Public Endpoints

Grafana:

`https://grafana.ferdeve.fit`

Prometheus:

`https://prometheus.ferdeve.fit`

Both endpoints use:

- NGINX Ingress
- Route 53 DNS
- cert-manager
- Let's Encrypt TLS certificates

## Files

### monitoring.env

Contains shared configuration such as:

- namespace
- Helm repository
- release name
- hostnames
- ingress class
- ClusterIssuer

### values.yaml

Contains Helm overrides for:

- Prometheus
- Grafana
- resource requests and limits
- ingress
- TLS
- metrics components

### install.sh

Installs the monitoring stack.

The script:

1. Validates local dependencies.
2. Checks Kubernetes connectivity.
3. Confirms NGINX Ingress exists.
4. Confirms the production ClusterIssuer is Ready.
5. Adds and updates the Prometheus Helm repository.
6. Renders the Helm chart before installation.
7. Performs validation checks.
8. Installs the monitoring stack.

### verify.sh

Verifies:

- Helm release
- monitoring Pods
- Prometheus resource
- Grafana Service
- Grafana and Prometheus Ingress
- TLS Secrets
- kube-state-metrics
- node-exporter

### uninstall.sh

Removes:

- Helm release
- monitoring namespace
- Prometheus
- Grafana
- kube-state-metrics
- node-exporter
- Prometheus Operator

## Installation

From the repository root:

```bash
./platform/monitoring/install.sh