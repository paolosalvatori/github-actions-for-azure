#!/bin/bash

servicePrincipalName="http://GitHubActionsApp"
gitHubSecretName="AZURE_CREDENTIALS_FROM_SCRIPT"
gitHubOwner="paolosalvatori"
gitHubRepo="github-actions-for-azure"
keyVaultName="BaboKeyVault"
keyVaultSecretName_gitHubPersonalAccessToken="GitHubPersonalAccessToken"
keyVaultSecretName_gitHubServicePrincipalCredentials="GitHubServicePrincipalCredentials"

# SubscriptionId of the current subscription
subscriptionId=$(az account show --query id --output tsv)

# Check if the service principal name already exists
echo "Checking if the [$servicePrincipalName] service principal already exists in the [$subscriptionId] subscription..."
az ad sp show --id $servicePrincipalName &>/dev/null

if [[ $? == 0 ]]; then
    echo "[$servicePrincipalName] service principal successfully already exists in the [$subscriptionId] subscription"
    echo "Retrieving [$servicePrincipalName] service principal credentials from the [$keyVaultSecretName_gitHubServicePrincipalCredentials] secret in [$keyVaultName] key vault..."
    servicePrincipalJson=$(az keyvault secret show \
        --name $keyVaultSecretName_gitHubServicePrincipalCredentials \
        --vault-name $keyVaultName \
        --query value \
        --output tsv)
    if [[ $? == 0 ]]; then
        echo "[$servicePrincipalName] service principal credentials successfully retrieved from the [$keyVaultSecretName_gitHubServicePrincipalCredentials] secret in [$keyVaultName] key vault"
    else
        echo "Failed to retrieve the [$servicePrincipalName] service principal credentials from the [$keyVaultSecretName_gitHubServicePrincipalCredentials] secret in [$keyVaultName] key vault"
        exit
    fi
else
    # Create service principal and assign contributor role at the subscription level
    echo "Creating the [$servicePrincipalName] service principal in the [$subscriptionId] subscription..."
    servicePrincipalJson=$(az ad sp create-for-rbac \
        --name $servicePrincipalName \
        --role contributor \
        --scopes /subscriptions/$subscriptionId \
        --sdk-auth true)
    if [[ $? == 0 ]]; then
        echo "[$servicePrincipalName] service principal successfully created in the [$subscriptionId] subscription"
        echo "Storing [$servicePrincipalName] service principal credentials in the [$keyVaultSecretName_gitHubServicePrincipalCredentials] secret in [$keyVaultName] key vault..."
        az keyvault secret set \
        --vault-name $keyVaultName \
        --name $keyVaultSecretName_gitHubServicePrincipalCredentials \
        --description "Azure service principal used by GitHub Actions workflows defined in the [$gitHubOwner/$gitHubRepo] GitHub repo" \
        --value "$servicePrincipalJson" 1>/dev/null
        if [[ $? == 0 ]]; then
            echo "[$servicePrincipalName] service principal credentials successfully stored in the [$keyVaultSecretName_gitHubServicePrincipalCredentials] secret in [$keyVaultName] key vault"
        else
            echo "Failed to store the [$servicePrincipalName] service principal credentials in the [$keyVaultSecretName_gitHubServicePrincipalCredentials] secret in [$keyVaultName] key vault"
            exit
        fi
    else
        echo "Failed to create the [$servicePrincipalName] service principal in the [$subscriptionId] subscription"
        exit
    fi
fi


# Retrieve the GitHub personal access token from Key Vault
echo "Retrieving the personal access token for the [$gitHubOwner] GitHub account from the [$keyVaultSecretName_gitHubPersonalAccessToken] secret in [$keyVaultName] key vault..."
gitHubPAT=$(az keyvault secret show \
    --name $keyVaultSecretName_gitHubPersonalAccessToken \
    --vault-name $keyVaultName \
    --query value \
    --output tsv)

if [[ $? == 0 ]]; then
    echo "Personal access token for the [$gitHubOwner] GitHub account successfully retrieved from the [$keyVaultSecretName_gitHubPersonalAccessToken] secret in [$keyVaultName] key vault"
else
    echo "Failed to retrieve the personal access token for the [$gitHubOwner] GitHub account from the [$keyVaultSecretName_gitHubPersonalAccessToken] secret in [$keyVaultName] key vault"
fi

# Verify that the service principal is not null
if [[ -z $servicePrincipalJson ]]; then
    echo "[$servicePrincipalName] service principal cannot be null or empty"
    exit
fi

# Verify that the personal access token is not null
if [[ -z $gitHubPAT ]]; then
    echo "The personal access token for the [$gitHubOwner] GitHub account cannot be null or empty"
    exit
fi