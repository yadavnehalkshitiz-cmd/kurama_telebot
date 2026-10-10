Write-Host "Installing Flutter, Java (OpenJDK), and Android Studio..."
choco install openjdk17 flutter androidstudio -y

Write-Host "Setting up Flutter..."
flutter channel stable
flutter upgrade

Write-Host "Accepting Android Licenses (this might require Android Studio to be opened first to install cmdline-tools)..."
Write-Output "y`ny`ny`ny`ny`ny`ny`ny" | flutter doctor --android-licenses

Write-Host "Running Flutter Doctor..."
flutter doctor

Write-Host "Setup finished! Please restart your terminal."
Pause
