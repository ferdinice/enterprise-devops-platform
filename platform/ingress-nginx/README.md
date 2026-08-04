# NGINX Ingress Controller

## Purpose

The NGINX Ingress Controller is the single HTTP/HTTPS entry point into the Kubernetes cluster.

It watches Kubernetes Ingress resources and routes external traffic to internal ClusterIP Services based on hostname or URL path.

## Why we use it

- Single external Load Balancer
- Host-based routing
- Path-based routing
- TLS termination
- Reduced AWS cost
- Centralized traffic management

## Repository Structure

```
platform/
└── ingress-nginx/
    ├── README.md
    └── values.yaml
```

## Status

- [ ] Helm installed
- [ ] Helm repository added
- [ ] NGINX Ingress installed
- [ ] LoadBalancer created
- [ ] DNS configured
- [ ] HTTPS enabled