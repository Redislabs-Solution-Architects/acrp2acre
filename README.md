# Azure Cache For Redis Stats

This is a stand-alone version of a script (`pullAzureCacheForRedisStats.py`) for pulling raw usage data from Azure Cache for Redis.

# Assumptions
We assume you have [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed.
Python 3.8 or greater is required.

### Running from source (Windows)

```
# Clone:
git clone https://github.com/Redislabs-Solution-Architects/acrp2acre.git

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

python pullAzureCacheForRedisStats.py
```

The output will be in a file called `AzureStats.xlsx` in the current directory.

### Running from source (Linux)
```
# Clone:
git clone https://github.com/Redislabs-Solution-Architects/acrp2acre.git

# Prepare virtualenv:
cd acrp2acre
python3 -m venv .env

# Activate virtualenv
source .env/bin/activate

# Install necessary libraries
pip3 install -r requirements.txt

# Log in to your Azure account
az login

#Execute 

python3 pullAzureCacheForRedisStats.py
```


