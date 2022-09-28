#!/bin/bash
kubectl delete namespace argocd
kubectl delete namespace sealed-secrets
kubectl delete namespace webapp
kubectl delete namespace external-dns
kubectl delete namespace kong
kubectl delete namespace cert-manager

