subscriptionId=$(az account show --query id --output tsv)

if [[ -z $1 ]]; then
    echo "The storage account name parameter cannot be null"
fi

filter="[?name=='$1'].name"
result=$(az storage account list --query "$filter"  --output tsv)

if [[ -z $result ]]; then
    echo "The ["$1"] storage account does not exist in the ["$subscriptionId"] subscription"
    exit 0
else
    echo "The ["$1"] storage account already exists in the ["$subscriptionId"] subscription"
    exit 0
fi