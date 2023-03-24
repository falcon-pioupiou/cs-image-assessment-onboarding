# AWS Image Assessment Onboarding


This script requires to be executed on the management account (to create the stackset at org level).

Default values:
```
Stackset & stack will be deployed in us-west-1
Name of the stack & Stackset: CrowdStrike-Image-Assessment-integration
Name of the role created: CrowdStrikeImageAssessmentRole
ExternalID is random
```

```bash
curl -sSL https://raw.githubusercontent.com/falcon-pioupiou/cs-image-assessment-onboarding/main/deploy-iam-role-org.sh | \ 
    CS_ACCOUNT_NUMBER=123456789012 \
    AWS_PROFILE=default \
    EXTERNAL_ID="your external ID" \
    bash
```

