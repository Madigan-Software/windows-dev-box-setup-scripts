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

# Get Visual Studio C++ Redistributables
_chocolatey-InstallOrUpdate -PackageId vcredist2015
