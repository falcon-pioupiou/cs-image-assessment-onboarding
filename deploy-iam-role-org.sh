#!/bin/bash

external_id=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c"${1:-32}";echo;)
aws_profile="default"
role_name="CrowdStrikeImageAssessmentRole"
stack_name="CrowdStrike-Image-Assessment-integration"
default_region="us-west-1"
csaccount=""

noformat="\\033[0m"
skyblue="\\033[38;5;117m"
deepskyblue="\\033[48;5;25m"
red="\\033[38;5;1m"
green="\\033[38;5;28m"

usage()
{
    echo "usage:
    CS_ACCOUNT_NUMBER=123456789012 $0

Required Env Variable:
    CS_ACCOUNT_NUMBER       You can find it when you start to onboard an ECR registry from the console
    
Optional Env Variable:
    AWS_PROFILE             Select the AWS profile to use to run this script
    DEFAULT_REGION          Allows you to select the region to deploy the stack and the stacksets (default: us-west-1)
    EXTERNAL_ID             Allows you to configure the external id (if not set it will generate a random External ID)
    STACK_NAME              Allows you to configure the stack name (default: CrowdStrike-Image-Assessment-integration)
    ROLE_NAME               Allows you to configure the role name created in your IAM (default: CrowdStrikeImageAssessmentRole)

Help Options:
    -h, --help display this help message"
    exit 2
}

if [ "${BASH_VERSION}" ]; then
  print_args="-e"
fi

function logi {
  echo ${print_args} "${skyblue}${1} ${noformat}"
}

function logn {
  echo ${print_args} "${deepskyblue}${1} ${noformat}"
}

function logs {
  echo ${print_args} "${green}${1} ${noformat}"
}

function loge {
  echo ${print_args} "${red}✖ ${1} ${noformat}"
}

function install_jq {
  logi "====> Installing jq..."
  if [[ "$1" == "windows" ]]; then
    loge "installing jq for windows is not supported"
    return 1
  fi
  {
    brew install jq
  } || {
    sudo apt-get update -qy && sudo apt-get install -qy jq
  } || {
    sudo apt update -qy && sudo apt install -qy jq
  } || {
    sudo yum update -qy && sudo yum install -qy jq
  } || {
    return 1
  }
}

function check_jq {
  if ! [[ -x "$(command -v jq)" ]]; then
    logn "jq not found"
    if [[ "$OSTYPE" == "linux-gnu" ]]; then
      install_jq "linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
      install_jq "darwin"
    elif [[ "$OSTYPE" == "cygwin" ]]; then
      install_jq "windows"
    elif [[ "$OSTYPE" == "msys" ]]; then
      install_jq "windows"
    elif [[ "$OSTYPE" == "win32" ]]; then
      install_jq "windows"
    elif [[ "$OSTYPE" == "freebsd"* ]]; then
      install_jq "linux"
    else
      loge "failed to install jq"
      return 1
    fi
    return $?
  else
    logs "jq found in path"
    return 0
  fi
}

function aws_stackset_self_managed_prerequisite {
    local account_id profile default_region
    account_id="${1}"
    profile="${2}"
    default_region="${3}"
    if ! aws iam get-role --role-name AWSCloudFormationStackSetAdministrationRole --profile "${profile}" >/dev/null 2>&1; then
        logi "Adding... AWSCloudFormationStackSetAdministrationRole"
        aws cloudformation create-stack --stack-name "AWSCloudFormationStackSetPrerequisiteAdministrationRole" \
            --template-url "https://s3.amazonaws.com/cloudformation-stackset-sample-templates-us-east-1/AWSCloudFormationStackSetAdministrationRole.yml" \
            --capabilities CAPABILITY_NAMED_IAM --profile "${profile}" --region "${default_region}" >/dev/null
        aws cloudformation wait stack-create-complete --stack-name "AWSCloudFormationStackSetPrerequisiteAdministrationRole" --profile "${profile}" --region "${default_region}"
    else
        logs "AWSCloudFormationStackSetAdministrationRole: OK!"
    fi
    if ! aws iam get-role --role-name AWSCloudFormationStackSetExecutionRole --profile "${profile}" >/dev/null 2>&1; then
        logi "Adding... AWSCloudFormationStackSetExecutionRole"
        aws cloudformation create-stack --stack-name "AWSCloudFormationStackSetPrerequisiteExecutionRole" \
            --parameters "ParameterKey=AdministratorAccountId,ParameterValue=${account_id}" \
            --template-url "https://s3.amazonaws.com/cloudformation-stackset-sample-templates-us-east-1/AWSCloudFormationStackSetExecutionRole.yml" \
            --capabilities CAPABILITY_NAMED_IAM --profile "${profile}" --region "${default_region}" >/dev/null
        aws cloudformation wait stack-create-complete --stack-name "AWSCloudFormationStackSetPrerequisiteExecutionRole" --profile "${profile}" --region "${default_region}"
    else
        logs "AWSCloudFormationStackSetExecutionRole: OK!"
    fi

}

function wait_for_operation {
  local count
  if ! test -z "${2}"; then
    count=0
    logi "Waiting for operation to finish...Deploying the IAM role in all child accounts"
    until aws cloudformation describe-stack-set-operation --stack-set-name "${1}" --operation-id "${2}" --profile "${3}" --region "${4}" 2>/dev/null | jq -e '.StackSetOperation | select(.Status=="SUCCEEDED" or .Status=="FAILED" or .Status=="STOPPED")' >/dev/null; do
        ((count=count+1)) # <= bug if ((count++))
        if ((count % 2 == 0)); then logi "Waiting for operation to finish...Deploying the IAM role in all child accounts...please be patient"; fi
        if ((count == 60)); then logi "exiting too long to wait... monitor the AWS StackSets to check for the full deployment status"; break; fi
        sleep 10
    done
    logs "🎉 StackSets deployed in all child accounts !"
  fi
}

function main {
    set -e
    check_jq

    if test -z "${CS_ACCOUNT_NUMBER}"; then
        loge "CS_ACCOUNT_NUMBER is missing and needed for this operation"
        logi "You can find it when you start to onboard an ECR registry from the console"
        logi ""
        usage
        exit 1
    else
        logs "\$CS_ACCOUNT_NUMBER => [${CS_ACCOUNT_NUMBER}]"
        csaccount="${CS_ACCOUNT_NUMBER}"
    fi

    # shellcheck disable=SC2153
    if ! test -z "${DEFAULT_REGION}"; then
        default_region="${DEFAULT_REGION}"
    fi
    logs "\$DEFAULT_REGION => [${default_region}]"

    # Generate a random External ID
    # shellcheck disable=SC2153
    if ! test -z "${EXTERNAL_ID}"; then
        external_id="${EXTERNAL_ID}"
    fi
    logs "\$EXTERNAL_ID => [${external_id}]"
    
    # shellcheck disable=SC2153
    if ! test -z "${AWS_PROFILE}"; then
        aws_profile="${AWS_PROFILE}"
    fi
    logs "\$AWS_PROFILE => [${aws_profile}]"

    # shellcheck disable=SC2153
    if ! test -z "${STACK_NAME}"; then
        stack_name="${STACK_NAME}"
    fi
    logs "\$STACK_NAME => [${stack_name}]"

    # shellcheck disable=SC2153
    if ! test -z "${ROLE_NAME}"; then
        role_name="${ROLE_NAME}"
    fi
    logs "\$ROLE_NAME => [${role_name}]"

    if ! aws organizations list-aws-service-access-for-organization --profile "${aws_profile}" | jq -e '.EnabledServicePrincipals[] | select(.ServicePrincipal=="member.org.stacksets.cloudformation.amazonaws.com")' >/dev/null; then
      loge "you must enable organizations access to operate a service managed stack set"
      logi 'open https://console.aws.amazon.com/cloudformation/#/stacksets and click "Enable trusted access"'
      exit 1
    fi

    logn "[>] Download the Cloud Formation template"
    curl -sSL https://raw.githubusercontent.com/falcon-pioupiou/cs-image-assessment-onboarding/main/cs-image-assessment-role.json -o crowdstrike-ia-integration.json

    stack_parameters=$(jq -Rn \
    --arg role_name "${role_name}" \
    --arg external_id "${external_id}" \
    --arg cs_account_number "${csaccount}" -c '[
  {ParameterKey: "RoleName", ParameterValue: $role_name},
  {ParameterKey: "ExternalID", ParameterValue: $external_id},
  {ParameterKey: "CSAccountNumber", ParameterValue: $cs_account_number}
  ] | [ .[] | select( .ParameterValue != "" )]')

    logn "[>] Checking AWS StackSets prerequisites"
    current_aws_account_id=$(aws sts get-caller-identity --query 'Account' --output text)
    aws_stackset_self_managed_prerequisite "${current_aws_account_id}" "${aws_profile}" "${default_region}"

    logn "[>] Creating the IAM Role in for the root account via a Stack"
    # StackSets doesn't deploy stack instances to the organization's management account, 
    # even if the management account is in your organization or in an OU in your organization.
    # So this is needed

    if ! aws cloudformation describe-stacks --stack-name "${stack_name}" --profile "${aws_profile}" --region "${default_region}" >/dev/null 2>&1; then
        aws cloudformation create-stack --stack-name "${stack_name}" \
        --template-body file://crowdstrike-ia-integration.json \
        --parameters "${stack_parameters}" \
        --capabilities CAPABILITY_NAMED_IAM --profile "${aws_profile}" --region "${default_region}" >/dev/null \
        && aws cloudformation wait stack-create-complete --stack-name "${stack_name}" --profile "${aws_profile}" --region "${default_region}"
    else
        logi "Stack in the management (root) account already exist. Skipping"
    fi

    logn "[>] Creating the IAM Role in for child accounts via StackSets"
    if ! aws cloudformation describe-stack-set --stack-set-name "${stack_name}" --profile "${aws_profile}" --region "${default_region}" >/dev/null 2>&1; then
        aws cloudformation create-stack-set --stack-set-name "${stack_name}" \
        --template-body file://crowdstrike-ia-integration.json \
        --description "Configure Image Assessment IAM role in child accounts" \
        --parameters "${stack_parameters}" \
        --permission-model SERVICE_MANAGED \
        --auto-deployment "Enabled=true,RetainStacksOnAccountRemoval=false" \
        --capabilities CAPABILITY_NAMED_IAM --profile "${aws_profile}" --region "${default_region}" >/dev/null

        operation_preferences="FailureTolerancePercentage=100,RegionConcurrencyType=PARALLEL,MaxConcurrentCount=20"
        ou_id=$(aws organizations list-roots --query 'Roots[].Id' --output text --profile "${aws_profile}")

        stack_operation_id=$(aws cloudformation create-stack-instances --stack-set-name "${stack_name}" \
            --regions "${default_region}" \
            --deployment-targets "OrganizationalUnitIds=${ou_id}" \
            --operation-preferences "${operation_preferences}" \
            --profile "${aws_profile}" --region "${default_region}" 2>/dev/null | jq -r '.OperationId' 2>/dev/null)

        wait_for_operation "${stack_name}" "${stack_operation_id}" "${aws_profile}" "${default_region}"
    else
        logi "StackSet already exist. Skipping"
    fi

    logs "✅ DONE !"
}

while [ $# != 0 ]; do
case "$1" in
    -h|--help)
    if [ -n "${1}" ]; then
        usage
    fi
    ;;
    --) # end argument parsing
    shift
    break
    ;;
esac
shift
done

# shellcheck disable=SC2119
main
