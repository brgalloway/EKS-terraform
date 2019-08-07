# EKS-terraform

### Targeting the autoscale group to temporarily turn off
```
terraform destory -target RESOURCE_TYPE.RESOURCE_NAME
```

### Connecting Kubernetes to Gitlab for CI/CD pipeline
To get the certificate from the cluster in AWS run
```
kubectl get secrets
kubectl get secret <secret name> -o jsonpath="{['data']['ca\.crt']}" | base64 --decode
```

