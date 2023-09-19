# Azure Cache For Redis Stats

## Python Version

This is a stand-alone version of a script (`pullAzureCacheForRedisStats.py`) for pulling raw usage data from Azure Cache for Redis.

### Python Prerequisites
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
python3 -m venv .venv

# Activate virtualenv
source .venv/bin/activate

# Install necessary libraries
pip3 install -r requirements.txt

# Log in to your Azure account
az login

#Execute 

python3 pullAzureCacheForRedisStats.py
```

## PowerShell Version

The PowerShell version of the script is experimental

### PowerShell Prerequisites

The Azure PowerShell Az module is required.
See [this page](https://learn.microsoft.com/en-us/powershell/azure/install-azure-powershell?view=azps-10.3.0) for installation instructions

This script has been tested on Windows PowerShell 5.1 and PowerShell 7.2

### Running
```
.\Pull-Azure-Cache-For-Redis-Stats.ps1
```