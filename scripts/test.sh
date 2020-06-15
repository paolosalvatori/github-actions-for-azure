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

# Install curl if not exists
result=$(command -v curl)
if [[ -z $result ]]; then
    sudo apt-get install -y curl
fi

# Install make if not exists
result=$(command -v make)
if [[ -z $result ]]; then
    sudo apt-get install -y make
fi

# Install cmake if not exists
result=$(command -v cmake)
if [[ -z $result ]]; then
    sudo apt-get install -y cmake
fi

# Install pip if not exists
result=$(command -v pip)
if [[ -z $result ]]; then
    sudo apt-get install -y pip
fi

# Install pip if not exists
result=$(command -v pip)
if [[ -z $result ]]; then
    sudo apt-get install -y pip
fi

# Install githubsecrets
result=$(pip show githubsecrets)
if [[ -z $result ]]; then
    pip install githubsecrets
fi

# Install and unzip libsodium library
if [[ -d ./libsodium-stable ]]; then
    echo "The libsodium library already exists"
else
    echo "Installing the libsodium library..."
    curl https://download.libsodium.org/libsodium/releases/LATEST.tar.gz -o LATEST.tar.gz
    tar -xvf LATEST.tar.gz
    cd ./libsodium-stable

    # Compile the library
    ./configure
    make && make check
    sudo make install
    sudo ldconfig
    cd ..
    echo "The libsodium library has been successfully compiled"
fi

# Download libsodium-file-crypter from GitHub
if [[ -d ./libsodium-file-crypter ]]; then
    echo "The libsodium-file-crypter tool already exists"
else
    echo "Installing the libsodium-file-crypter tool..."
    git clone https://github.com/jpiechowka/libsodium-file-crypter.git

    # Compile libsodium-file-crypter
    cd ./libsodium-file-crypter
    cmake .
    make
    cd ..
    echo "The libsodium-file-crypter tool has been successfully compiled"
fi

# Retrieve the public key from GitHub
echo "Retrieving the public key for Git Hub actions from the [$gitHubOwner/$gitHubRepo] GitHub repo"
echo "using a GET /repos/:owner/:repo/actions/secrets/public-key call..."
publicKeyPayload=$(curl \
    -H "Authorization: token $gitHubPAT" \
    https://api.github.com/repos/paolosalvatori/github-actions-for-azure/actions/secrets/public-key)

publicKeyBase64=$(echo $publicKeyPayload | jq -r .key)
publicKeyId=$(echo $publicKeyPayload | jq -r .key_id)

if [[ -n $publicKeyBase64 && -n $publicKeyId ]]; then
    echo "Public key for Git Hub actions successfully retrieved from the [$gitHubOwner/$gitHubRepo] GitHub repo"
else
    echo "Failed to retrieve the public key for Git Hub actions from the [$gitHubOwner/$gitHubRepo] GitHub repo"
    exit
fi

# Encrypt the service principal
publicKey=$(echo -n $publicKeyBase64 | base64 -d)
echo $servicePrincipalJson >plaintext.txt
./libsodium-file-crypter/libsodium-file-crypter -e -o encrypted.txt plaintext.txt $publicKey
encryptedValue=$(base64 encrypted.txt)
rm plaintext.txt
rm encrypted.txt

echo "encryptedValue=$encryptedValue"

# Store the service principal as a secret in the GitHub repo
echo "Storing [$servicePrincipalName] service principal as a secret in the [$gitHubOwner/$gitHubRepo] GitHub repo"
echo "using a PUT /repos/:owner/:repo/actions/secrets/:secret_name call..."
url="https://api.github.com/repos/$gitHubOwner/$gitHubRepo/actions/secrets/$gitHubSecretName"
payload=$(printf "{\n\t\"encrypted_value\": \"$encryptedValue\",\n\t\"key_id\": \"$publicKeyId\"\n}")
echo -e $payload
echo $url
curl \
    -H "Authorization: token $gitHubPAT" \
    -X PUT \
    -d "$payload" \
    $url
if [[ $? == 0 ]]; then
    echo "[$servicePrincipalName] service principal successfully stored as a secret in the [$gitHubOwner/$gitHubRepo] GitHub repo"
else
    echo "Failed to store the [$servicePrincipalName] service principal as a secret in the [$gitHubOwner/$gitHubRepo] GitHub repo"
fi
