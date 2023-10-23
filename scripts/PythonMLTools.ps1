if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }

# Install python
# _chocolatey-InstallOrUpdate -PackageId python
Invoke-ExternalCommand -Command { choco install -y python --version=3.5.4 }

# Refresh path
refreshenv

# Update pip
Invoke-ExternalCommand -Command { python -m pip install --upgrade pip }

# Install ML related python packages through pip
Invoke-ExternalCommand -Command { pip install numpy }
Invoke-ExternalCommand -Command { pip install scipy }
Invoke-ExternalCommand -Command { pip install pandas }
Invoke-ExternalCommand -Command { pip install matplotlib }
Invoke-ExternalCommand -Command { pip install tensorflow }
Invoke-ExternalCommand -Command { pip install keras }
#pre-commit framework hooks
#Invoke-ExternalCommand -Command { pip install pre-commit }

<#
Create a .pre-commit-config.yaml file within your project. 
This file contains the pre-commit hooks you want to run every time before you commit. 
It looks like this:

repos:
-   repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v3.2.0
    hooks:
    -   id: trailing-whitespace
    -   id: mixed-line-ending
-   repo: https://github.com/psf/black
    rev: 20.8b1
    hooks:
    -   id: black
pre-commit will look in those two repositories with the specified git tags for a file called .pre-commit-hooks.yaml. 
Within that file can be arbitrary many hooks defined. They all need an id so that you can choose which ones you want to use. 
The above git-commit config would use 3 hooks.

Finally, you need to run pre-commit install to tell pre-commit to always run for this repository.

pre-commit will abort the commit if it changes anything. 
So you can still have a look at the code and check if the changes are reasonable. You can also choose not to run pre-commit by

git commit --no-verify
#>

# Get Visual Studio C++ Redistributables
_chocolatey-InstallOrUpdate -PackageId vcredist2015
