# AWS Image Assessment Onboarding


This script requires to be executed on the management account (to create the stackset at org level).

```bash
curl -sSL https://raw.githubusercontent.com/falcon-pioupiou/cs-image-assessment-onboarding/main/deploy-iam-role-org.sh | \ 
    CS_ACCOUNT_NUMBER=123456789012 \
    bash
```

