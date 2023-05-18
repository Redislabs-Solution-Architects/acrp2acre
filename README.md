# Azure Cache For Redis Stats

This is a stand-alone version of a script (`pullAzureCacheForRedisStats.py`) for pulling raw usage data from Azure Cache for Redis.

# Assumptions
We assume you have [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed.

### Running from source

```
# Clone:
git clone https://github.com/kkrueger/acrp2acre

# Prepare virtualenv:
cd acrp2acre
python -m venv .\venv

# Activate virtualenv
.\venv\Scripts\activate.bat

# Install necessary libraries
pip install -r requirements.txt

# Log in to your Azure account
az login

#Execute 

python pullAzureCacheForRedisStatus.py
```

The output will be in a file called `AzureStats.xlsx` in the current directory.

### Docker
Under construction

